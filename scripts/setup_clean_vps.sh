#!/bin/bash
# Fresh VPS install for Fratelanza CRM at crm.fratelanza.com
# Default: Option A (localhost:16350 + existing nginx). No port 80 conflict.
exec "$(dirname "$0")/setup_option_a.sh" "$@"
