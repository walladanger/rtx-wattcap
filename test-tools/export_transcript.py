#!/usr/bin/env python3
"""Export a slice of the session transcript (JSONL) to exact-fidelity Markdown + JSON.

Kept verbatim: every user message you typed, every visible assistant reply,
every tool call (full inputs, which include the full source of every file
written) and every tool result (full text, images saved as files).

Left out: the assistant's private reasoning blocks and app-injected context
(<system-reminder> blocks: memory snapshot, timezone, tool/skill listings,
system prompt snapshots, token counters). Those are not part of the visible
chat. Each omission is counted in the header.
"""
import base64, json, os, re, sys, hashlib

SR = re.compile(r'<system-reminder>.*?</system-reminder>', re.S)
QUEUED = re.compile(r'<system-reminder>\s*The user sent a new message while you were working:\n(.*?)\n\nIt arrived during this turn', re.S)


def fence_for(text, lang=''):
    runs = re.findall(r'`+', text)
    n = max([3] + [len(r) + 1 for r in runs])
    f = '`' * n
    return f + lang, f


def code(text, lang=''):
    a, b = fence_for(text, lang)
    if not text.endswith('\n'):
        text += '\n'
    return f'{a}\n{text}{b}\n'


LANG = {'.py': 'python', '.ps1': 'powershell', '.cs': 'csharp', '.cmd': 'bat', '.bat': 'bat',
        '.md': 'markdown', '.json': 'json', '.toml': 'toml', '.txt': 'text', '.mjs': 'javascript',
        '.js': 'javascript', '.sh': 'bash', '.html': 'html'}


def lang_of(path):
    return LANG.get(os.path.splitext(path or '')[1].lower(), '')


def main(jsonl, start, end, outdir, title):
    rows = [json.loads(l) for l in open(jsonl, encoding='utf-8')]
    end = len(rows) if end < 0 else end
    img_dir = os.path.join(outdir, 'images')
    os.makedirs(img_dir, exist_ok=True)
    tool_names = {}
    for r in rows:
        if r.get('type') == 'assistant':
            for b in r['message'].get('content', []) or []:
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    tool_names[b['id']] = (b['name'], b.get('input', {}))

    md = []
    js = []
    stats = {'thinking_blocks_omitted': 0, 'system_reminders_stripped': 0, 'images_saved': 0,
             'tool_calls': 0, 'tool_results': 0, 'user_messages': 0, 'assistant_text_blocks': 0,
             'skill_documents_loaded': 0}
    img_n = [0]
    last_role = [None]

    def save_img(src, hint):
        img_n[0] += 1
        mt = src.get('media_type', 'image/png')
        ext = {'image/png': '.png', 'image/gif': '.gif', 'image/jpeg': '.jpg', 'image/webp': '.webp'}.get(mt, '.bin')
        name = f'{img_n[0]:03d}-{hint}{ext}'
        with open(os.path.join(img_dir, name), 'wb') as f:
            f.write(base64.b64decode(src['data']))
        stats['images_saved'] += 1
        return 'images/' + name

    def head(role, ts, idx):
        if last_role[0] != role:
            md.append(f'\n---\n\n## {"USER" if role == "user" else "ASSISTANT"}  \n`{ts}` · entry {idx}\n')
            last_role[0] = role

    for idx in range(start, end):
        r = rows[idx]
        t = r.get('type')
        ts = r.get('timestamp', '')
        if t == 'attachment':
            a = r['attachment']
            if a.get('type') == 'file':
                head('user', ts, idx)
                fn = a.get('filename', '')
                md.append(f'\n> 📎 **Attached file:** `{fn}` (content included in this zip)\n')
                js.append({'entry': idx, 'timestamp': ts, 'role': 'user', 'kind': 'attached_file', 'path': fn})
            elif a.get('type') == 'inlined_image_paths':
                js.append({'entry': idx, 'timestamp': ts, 'role': 'user', 'kind': 'image_paths', 'paths': a.get('paths')})
            continue
        if t not in ('user', 'assistant'):
            continue
        msg = r['message']
        content = msg.get('content')
        blocks = [{'type': 'text', 'text': content}] if isinstance(content, str) else (content or [])
        rec = {'entry': idx, 'uuid': r.get('uuid'), 'timestamp': ts, 'role': t, 'blocks': []}

        if t == 'user':
            is_meta = bool(r.get('isMeta'))
            for b in blocks:
                bt = b.get('type')
                if bt == 'text':
                    raw = b.get('text', '')
                    for q in QUEUED.findall(raw):
                        head('user', ts, idx)
                        stats['user_messages'] += 1
                        md.append(f'\n*(typed while the assistant was working)*\n\n{q.strip()}\n')
                        rec['blocks'].append({'type': 'queued_user_message', 'text': q.strip()})
                    n = len(SR.findall(raw))
                    stats['system_reminders_stripped'] += n
                    txt = SR.sub('', raw).strip()
                    if not txt:
                        continue
                    if is_meta and txt.startswith('Base directory for this skill'):
                        stats['skill_documents_loaded'] += 1
                        head('user', ts, idx)
                        first = txt.splitlines()[0]
                        md.append(f'\n<details><summary>📘 Skill document loaded into the chat ({first})</summary>\n\n'
                                  + code(txt, 'markdown') + '\n</details>\n')
                        rec['blocks'].append({'type': 'skill_document', 'text': txt})
                        continue
                    head('user', ts, idx)
                    stats['user_messages'] += 1
                    label = '*(app/harness message)*\n\n' if is_meta else ''
                    md.append('\n' + label + txt + '\n')
                    rec['blocks'].append({'type': 'text', 'text': txt, 'meta': is_meta})
                elif bt == 'image':
                    head('user', ts, idx)
                    p = save_img(b['source'], 'user-image')
                    md.append(f'\n![user image]({p})\n')
                    rec['blocks'].append({'type': 'image', 'file': p})
                elif bt == 'tool_result':
                    stats['tool_results'] += 1
                    name, _ = tool_names.get(b.get('tool_use_id'), ('?', {}))
                    head('assistant', ts, idx)  # results belong to the assistant's working turn
                    parts = b.get('content')
                    parts = [{'type': 'text', 'text': parts}] if isinstance(parts, str) else (parts or [])
                    out_items = []
                    queued = []
                    md.append(f'\n<details><summary>⬅️ Result of <code>{name}</code>'
                              + (' (error)' if b.get('is_error') else '') + '</summary>\n\n')
                    for pb in parts:
                        if pb.get('type') == 'text':
                            rawt = pb.get('text', '')
                            for q in QUEUED.findall(rawt):
                                queued.append(q.strip())
                            txt = SR.sub('', rawt)
                            if txt.strip():
                                md.append(code(txt, 'text'))
                                out_items.append({'type': 'text', 'text': txt})
                        elif pb.get('type') == 'image':
                            pth = save_img(pb['source'], 'tool-result')
                            md.append(f'\n![tool result image]({pth})\n')
                            out_items.append({'type': 'image', 'file': pth})
                    md.append('\n</details>\n')
                    for q in queued:
                        stats['user_messages'] += 1
                        md.append(f'\n> 👤 **USER (typed while the assistant was working; delivered with this tool result):**\n>\n> {q}\n')
                        rec['blocks'].append({'type': 'queued_user_message', 'text': q})
                    queued.clear()
                    rec['blocks'].append({'type': 'tool_result', 'tool': name, 'tool_use_id': b.get('tool_use_id'),
                                          'is_error': bool(b.get('is_error')), 'content': out_items})
        else:
            for b in blocks:
                bt = b.get('type')
                if bt in ('thinking', 'redacted_thinking'):
                    stats['thinking_blocks_omitted'] += 1
                    continue
                head('assistant', ts, idx)
                if bt == 'text':
                    stats['assistant_text_blocks'] += 1
                    md.append('\n' + b.get('text', '') + '\n')
                    rec['blocks'].append({'type': 'text', 'text': b.get('text', '')})
                elif bt == 'tool_use':
                    stats['tool_calls'] += 1
                    name, inp = b['name'], b.get('input', {})
                    md.append(f'\n**➡️ Tool call:** `{name}`\n')
                    if name == 'Write':
                        md.append(f'\nFile: `{inp.get("file_path")}`\n\n' + code(inp.get('content', ''), lang_of(inp.get('file_path'))))
                    elif name == 'Edit':
                        md.append(f'\nFile: `{inp.get("file_path")}`' + (' (replace all)' if inp.get('replace_all') else '') +
                                  '\n\nOld:\n' + code(inp.get('old_string', ''), lang_of(inp.get('file_path'))) +
                                  '\nNew:\n' + code(inp.get('new_string', ''), lang_of(inp.get('file_path'))))
                    elif name == 'Bash':
                        if inp.get('description'):
                            md.append(f'\n*{inp["description"]}*\n\n')
                        md.append(code(inp.get('command', ''), 'bash'))
                    elif name in ('SendUserMessage',):
                        md.append('\n' + inp.get('message', '') + '\n')
                    else:
                        md.append(code(json.dumps(inp, indent=2, ensure_ascii=False), 'json'))
                    rec['blocks'].append({'type': 'tool_use', 'id': b['id'], 'name': name, 'input': inp})
        if rec['blocks']:
            js.append(rec)

    header = [f'# {title}: exact transcript\n',
              f'Source: session transcript entries {start}–{end - 1} (of {len(rows)}).  ',
              'Everything visible in the chat is verbatim: your messages, the replies, every tool call with its full '
              'input (including the complete source of every file written) and every tool result. Images are saved in '
              '`images/`.\n',
              'Omitted: the assistant\'s private reasoning blocks and app-injected context blocks '
              '(`<system-reminder>`: memory snapshot, timezone, tool and skill listings, token counters, system prompt snapshots).\n',
              '| Count | Value |', '|---|---|'] + [f'| {k} | {v} |' for k, v in stats.items()] + ['']
    with open(os.path.join(outdir, 'transcript.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(header) + ''.join(md))
    with open(os.path.join(outdir, 'transcript.json'), 'w', encoding='utf-8') as f:
        json.dump({'title': title, 'entries': [start, end - 1], 'stats': stats, 'messages': js}, f, indent=1, ensure_ascii=False)
    print(title, stats)


if __name__ == '__main__':
    main(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5])
