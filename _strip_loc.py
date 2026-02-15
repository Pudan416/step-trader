#!/usr/bin/env python3
"""Strip all loc(appLanguage, ...) calls, replacing with the English string argument."""
import re
import sys
import glob

def find_string_end(s, pos):
    """Find end of Swift string starting at pos (opening quote). Returns index of closing quote or -1."""
    if pos >= len(s) or s[pos] != '"':
        return -1
    i = pos + 1
    while i < len(s):
        c = s[i]
        if c == '\\':
            if i + 1 < len(s) and s[i + 1] == '(':
                # String interpolation \(...)
                depth = 1
                i += 2
                while i < len(s) and depth > 0:
                    if s[i] == '(':
                        depth += 1
                    elif s[i] == ')':
                        depth -= 1
                        if depth == 0:
                            break
                    elif s[i] == '"':
                        end = find_string_end(s, i)
                        if end == -1:
                            return -1
                        i = end
                    i += 1
                if depth > 0:
                    return -1
                i += 1  # skip past the closing )
                continue
            else:
                i += 2
                continue
        elif c == '"':
            return i
        else:
            i += 1
    return -1

def process_file(content):
    pattern = re.compile(r'(?:Steps4\.)?loc\(\s*appLanguage\s*,\s*')
    replacements = []

    for match in pattern.finditer(content):
        start = match.start()
        after_match = match.end()

        if after_match >= len(content) or content[after_match] != '"':
            continue

        str_end = find_string_end(content, after_match)
        if str_end == -1:
            continue

        first_arg = content[after_match:str_end + 1]

        j = str_end + 1
        while j < len(content) and content[j] in ' \t\n':
            j += 1

        if j >= len(content):
            continue

        if content[j] == ')':
            # 2-arg: loc(appLanguage, "text")
            replacements.append((start, j + 1, first_arg))
        elif content[j] == ',':
            # 3-arg: loc(appLanguage, "en", "ru")
            k = j + 1
            while k < len(content) and content[k] in ' \t\n':
                k += 1
            if k < len(content) and content[k] == '"':
                str2_end = find_string_end(content, k)
                if str2_end != -1:
                    m = str2_end + 1
                    while m < len(content) and content[m] in ' \t\n':
                        m += 1
                    if m < len(content) and content[m] == ')':
                        replacements.append((start, m + 1, first_arg))

    # Apply replacements in reverse order
    result = content
    for start, end, replacement in reversed(replacements):
        result = result[:start] + replacement + result[end:]
    return result, len(replacements)

files = glob.glob('StepsTrader/**/*.swift', recursive=True)
files += glob.glob('Steps4UITests/**/*.swift', recursive=True)

total = 0
for filepath in sorted(files):
    with open(filepath, 'r') as f:
        content = f.read()
    new_content, count = process_file(content)
    if count > 0:
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"  {filepath}: {count} replacements")
        total += count

print(f"\nTotal: {total} loc() calls replaced")
