#!/bin/bash

# Wait for OpenRazer and the keyboard
for i in {1..30}; do
    if /usr/bin/polychromatic-cli --list-devices 2>/dev/null | grep -q "Razer Cynosa Lite"; then
        break
    fi
    sleep 2
done

# Apply JITTER static red
/usr/bin/polychromatic-cli \
    --device keyboard \
    --zone main \
    --option static \
    --colours "#FF0000"
