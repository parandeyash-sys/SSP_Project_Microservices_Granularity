import os
import glob
import re

files = glob.glob('configs/*.toml')
for file_path in files:
    with open(file_path, 'r') as f:
        content = f.read()

    # We need to ensure that `colocate = [` and its array are within [serviceweaver]
    # The easiest way is to find `[multi]` or `[ssh]` and move them AFTER `colocate` array
    # Let's extract the `[multi]` or `[ssh]` block and append it to the end.

    # Match `[multi]` or `[ssh]` block (everything from the header until the next `[` or EOF)
    pattern = re.compile(r'(\[(?:multi|ssh)\].*?)(?=colocate = \[)', re.DOTALL)
    
    match = pattern.search(content)
    if match:
        block = match.group(1)
        # remove block from where it was
        content = content.replace(block, '')
        # append it at the end
        content = content + '\n\n' + block
        
        with open(file_path, 'w') as f:
            f.write(content)
            
print(f"Fixed {len(files)} config files.")
