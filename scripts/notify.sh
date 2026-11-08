#!/bin/sh
# Sends Martin a DM on at-chat: scripts/notify.sh 'message, with a link to the thread'
#
# For Claude threads (see .claude/settings.json). The token comes from the environment
# here, not from the command line, so the command a thread runs has no secret in it
# and matches the allow rule. Does nothing if AT_CHAT_NOTIFY_TOKEN isn't set.
[ -n "$AT_CHAT_NOTIFY_TOKEN" ] || exit 0
exec curl -sS -X POST https://at-chat.app/_r/notify-admins \
    -H "content-type: text/plain" \
    -H "x-notify-token: $AT_CHAT_NOTIFY_TOKEN" \
    --data-raw "$*"
