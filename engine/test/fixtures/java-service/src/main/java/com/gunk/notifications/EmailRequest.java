package com.gunk.notifications;
record EmailRequest(String to, String template) {}
record EmailResult(String to, String status) {}
