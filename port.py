#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Port reverse-skill -> DeepSeek Harness (dsh) skill layout.

- 1:1 copy of skills/ and CTF-Sandbox-Orchestrator/ (preserves all relative links)
- Normalize YAML frontmatter for dsh (lift metadata.user-invocable -> top-level
  user-invocable; when_to_use -> whenToUse; keep allowed-tools/license/compatibility
  as tolerated extras). Skill BODIES are never rewritten.
- Restructure the router skill (skills/SKILL.md) into a proper <name>/SKILL.md dir
  so dsh discovers it, fixing its internal doc links to ../ (docs stay at skills/ level).
"""
import os, re, shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "reverse-skill")
DST = os.path.join(ROOT, "dsh-port")

def copy_tree(src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)

def normalize_frontmatter(text):
    if not text.startswith("---"):
        return text, False
    end = text.find("\n---", 3)
    if end == -1:
        return text, False
    fm = text[3:end]
    body = text[end + 4:]
    lines = fm.split("\n")
    out = []
    user_invocable = None
    i = 0
    changed = False
    while i < len(lines):
        line = lines[i]
        if line.strip() == "metadata:":
            j = i + 1
            while j < len(lines) and (lines[j].startswith(" ") or lines[j].startswith("\t")):
                if "user-invocable" in lines[j]:
                    m = re.search(r'user-invocable:\s*"?([^"\n]+)"?', lines[j])
                    if m:
                        user_invocable = m.group(1).strip().strip('"')
                j += 1
            i = j
            changed = True
            continue
        if re.match(r"^when_to_use:", line):
            line = re.sub(r"^when_to_use:", "whenToUse:", line)
            changed = True
        out.append(line)
        i += 1
    fm2 = "\n".join(out)
    if user_invocable is not None:
        fm2 = fm2.rstrip("\n") + f"\nuser-invocable: {user_invocable}\n"
        changed = True
    return "---\n" + fm2 + "---\n" + body, changed

def restructure_router(dst):
    src = os.path.join(dst, "skills", "SKILL.md")
    if not os.path.exists(src):
        return
    d = os.path.join(dst, "skills", "reverse-skill-router")
    os.makedirs(d, exist_ok=True)
    t = open(src, encoding="utf-8").read()
    # docs (MASTER-ROUTING.md / routing.md / RULES.md / tool-index.md / ops/ / scripts/)
    # live at skills/ level; router now one level deeper -> prefix ../
    t = re.sub(r"(?<![\w/.])(MASTER-ROUTING\.md)", r"../\1", t)
    t = re.sub(r"(?<![\w/.])(routing\.md)", r"../\1", t)
    t = re.sub(r"(?<![\w/.])(RULES\.md)", r"../\1", t)
    t = re.sub(r"(?<![\w/.])(tool-index\.md)", r"../\1", t)
    t = re.sub(r"(?<![\w/.])(ops/)", r"../\1", t)
    t = re.sub(r"(?<![\w/.])(scripts/)", r"../\1", t)
    # CTF lives at repo root -> now two levels up
    t = t.replace("../CTF-Sandbox-Orchestrator/", "../../CTF-Sandbox-Orchestrator/")
    open(os.path.join(d, "SKILL.md"), "w", encoding="utf-8").write(t)
    os.remove(src)

def main():
    copy_tree(os.path.join(SRC, "skills"), os.path.join(DST, "skills"))
    copy_tree(os.path.join(SRC, "CTF-Sandbox-Orchestrator"),
              os.path.join(DST, "CTF-Sandbox-Orchestrator"))

    count = 0
    norm = 0
    for r, _, files in os.walk(os.path.join(DST)):
        for f in files:
            if f == "SKILL.md":
                p = os.path.join(r, f)
                t = open(p, encoding="utf-8").read()
                nt, ch = normalize_frontmatter(t)
                if ch:
                    open(p, "w", encoding="utf-8").write(nt)
                    norm += 1
                count += 1
    restructure_router(DST)
    print(f"SKILL.md total: {count}")
    print(f"frontmatter normalized: {norm}")

if __name__ == "__main__":
    main()
