package com.gunk.reports;
class ReportExporter { ReportFile export(String accountId) { return new ReportFile(accountId + ".csv"); } }
record ReportFile(String path) {}
