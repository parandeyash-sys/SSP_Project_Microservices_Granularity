#!/usr/bin/env python3
import sys
import yaml

# Usage: ./inject_nodes.py input.yaml output.yaml node1_groups node2_groups [node1_name] [node2_name]

if len(sys.argv) < 5:
    print("Usage: ./inject_nodes.py input.yaml output.yaml node1_groups node2_groups [node1_name] [node2_name]")
    sys.exit(1)

input_yaml = sys.argv[1]
output_yaml = sys.argv[2]
node1_groups = sys.argv[3].split(",")
node2_groups = sys.argv[4].split(",")

# Dynamic node names (defaults to minikube and minikube-m02)
node1_name = sys.argv[5] if len(sys.argv) > 5 else "minikube"
node2_name = sys.argv[6] if len(sys.argv) > 6 else "minikube-m02"

with open(input_yaml, 'r') as f:
    docs = list(yaml.load_all(f, Loader=yaml.FullLoader))

# Filter out None documents and process
processed_docs = []
for doc in docs:
    if not doc:
        continue
    
    if doc.get('kind') == 'Deployment':
        name = doc.get('metadata', {}).get('name', '')
        target_node = None
        
        for g in node1_groups:
            if name.startswith(f"ob-{g}-"):
                target_node = node1_name
                break
        
        if not target_node:
            for g in node2_groups:
                if name.startswith(f"ob-{g}-"):
                    target_node = node2_name
                    break
        
        if target_node:
            spec = doc.setdefault('spec', {})
            template = spec.setdefault('template', {})
            template_spec = template.setdefault('spec', {})
            template_spec['nodeSelector'] = {'kubernetes.io/hostname': target_node}
    
    processed_docs.append(doc)

with open(output_yaml, 'w') as f:
    yaml.dump_all(processed_docs, f, default_flow_style=False, sort_keys=False)
