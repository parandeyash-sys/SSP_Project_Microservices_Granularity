#!/usr/bin/env python3
import sys
import yaml

# Usage: ./inject_nodes.py input.yaml output.yaml node1_patterns node2_patterns
# nodeX_patterns: comma-separated list of group names or component names to map to node X

if len(sys.argv) < 5:
    print("Usage: ./inject_nodes.py input.yaml output.yaml node1_groups node2_groups")
    sys.exit(1)

input_yaml = sys.argv[1]
output_yaml = sys.argv[2]
node1_groups = sys.argv[3].split(",")
node2_groups = sys.argv[4].split(",")

with open(input_yaml, 'r') as f:
    # Service Weaver generates a multi-document YAML
    docs = list(yaml.load_all(f, Loader=yaml.FullLoader))

for doc in docs:
    if not doc or doc.get('kind') != 'Deployment':
        continue
    
    name = doc.get('metadata', {}).get('name', '')
    target_node = None
    
    # Match deployment name to group
    # Service Weaver names deployments like "boutique-groupname" or just "groupname"
    # We'll check if any of our group patterns are in the deployment name
    for g in node1_groups:
        if g in name:
            target_node = "minikube"
            break
    
    if not target_node:
        for g in node2_groups:
            if g in name:
                target_node = "minikube-m02"
                break
    
    if target_node:
        spec = doc.setdefault('spec', {})
        template = spec.setdefault('template', {})
        template_spec = template.setdefault('spec', {})
        template_spec['nodeSelector'] = {'kubernetes.io/hostname': target_node}

with open(output_yaml, 'w') as f:
    yaml.dump_all(docs, f)
