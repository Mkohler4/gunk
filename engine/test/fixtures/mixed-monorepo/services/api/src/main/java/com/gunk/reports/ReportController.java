package com.gunk.reports;
class ReportController { private final ReportExporter exporter = new ReportExporter(); ReportFile export(String accountId) { return exporter.export(accountId); } }
