# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-03-24

### Added
- Recursive search in subdirectories for log files
- Interactive mode for guided search setup
- Support for multiple search terms with AND/OR logic
- Advanced filters: application, database, action, date range
- Export functionality to CSV, JSON, and TXT formats
- Detailed search statistics and progress indicators
- Colored console output for better readability
- Configurable result limits
- Case-sensitive search option
- Debug mode for troubleshooting

### Fixed
- Improved log line parsing to handle queries with commas
- Better date parsing with multiple format support
- Fixed issues with large file processing using StreamReader

### Changed
- Enhanced performance for large log files
- Updated banner to reflect version 2.0 (Fixed)

### Technical Details
- Requires PowerShell 5.1 or higher
- Supports Amazon RDS audit log format
- Environment-based organization (prod/preprod)</content>
<parameter name="filePath">c:\Users\Matias\Desktop\log_search_engine\CHANGELOG.md