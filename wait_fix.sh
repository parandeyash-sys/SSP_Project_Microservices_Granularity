sed -i 's/curl -sf "${url}" > \/dev\/null 2>&1/curl -s --max-time 1 "${url}" > \/dev\/null 2>\&1/g' 02_run_2vm_experiments.sh
