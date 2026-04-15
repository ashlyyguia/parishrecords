@echo off
REM EmailJS Configuration for ParishRecord Backend
set EMAILJS_SERVICE_ID=service_ck0mxc9
set EMAILJS_TEMPLATE_ID=template_mxaaua5
set EMAILJS_PUBLIC_KEY=pffQo-NDfeKxhb78r
set EMAILJS_PRIVATE_KEY=ypwIOtR-vzwQalsWlolx4
set EMAILJS_FROM_NAME=ParishRecord
set EMAILJS_REPLY_TO=noreply@parishrecord.com

echo EmailJS environment variables set!
echo Starting backend server...
cd %~dp0
npm start
