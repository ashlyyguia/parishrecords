#!/bin/bash
# EmailJS Configuration for ParishRecord Backend
export EMAILJS_SERVICE_ID=service_ck0mxc9
export EMAILJS_TEMPLATE_ID=template_mxaaua5
export EMAILJS_PUBLIC_KEY=pffQo-NDfeKxhb78r
export EMAILJS_PRIVATE_KEY=ypwIOtR-vzwQalsWlolx4
export EMAILJS_FROM_NAME=ParishRecord
export EMAILJS_REPLY_TO=noreply@parishrecord.com

echo "EmailJS environment variables set!"
echo "Starting backend server..."
cd "$(dirname "$0")"
npm start
