#!/bin/bash

write_disk_info() {
    if ! DISK_LAYOUT=$(diskutil list -plist | python3 -c "import sys,plistlib,json; print(json.dumps(plistlib.load(sys.stdin.buffer)))" 2>/dev/null); then
        DISK_LAYOUT="{}"
    fi

    FS_SIZE=$(df -k | tail -n +2 | awk '
        BEGIN { print "[" }
        {
            if (NR > 1) printf ","
            use_value = $5
            gsub(/%/, "", use_value)
            mount = $6
            if (NF > 6) {
                for (i = 7; i <= NF; i++) {
                    mount = mount " " $i
                }
            }
            gsub(/\\/,"\\\\",mount)
            gsub(/"/,"\\\"",mount)
            gsub(/\\/,"\\\\",$1)
            gsub(/"/,"\\\"",$1)
            printf "{\"fs\":\"%s\",\"size\":%d,\"used\":%d,\"available\":%d,\"use\":%d,\"mount\":\"%s\"}",
                $1, $2 * 1024, $3 * 1024, $4 * 1024, use_value, mount
        }
        END { print "]" }')

    cat > /tmp/nomad-disk-info.json << EOF
{
"diskLayout": $DISK_LAYOUT,
"fsSize": $FS_SIZE
}
EOF
}

while true; do
    write_disk_info

    if [[ "$1" == "--once" ]]; then
        exit 0
    fi

    sleep 300
done
