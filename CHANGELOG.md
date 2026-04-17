# Changelog

## v0.10.4 (2026-04-17)
* Add "Save as Work-in-Progress" (Smart Drafting) for Wiki Pages #6
* End support for Ruby 2.6 and Redmine 4.1 #17
* Feature: Automatically cancel pending approvals when a page is published #15
* Feature: implement full REST API, including OpenAPI documentation, Endpoints: index, history, status, start, grant, forward, publish, permissions #11
* Fix: Incorrect redirect to draft version when module was previously disabled #13
* Refactor database schema: Rename page_id, version column, add activity index, and introduce revision number #14
* Refactor: Align Wiki Approval notifications with User Mail Settings (All, Selected, None) #16
* Refactor: Decouple Wiki Saving from Publishing Logic and Improve API Responses #18 permission remove create draft, permission add Publish wiki draft

## v0.9.1 (2026-02-20)
* Add Mermaid-based Workflow Status Flow diagram to README #10
* Add email notifications for workflow restarts, step user changes or forward approval #5
* Fix: Prevent deletion of parallel approvers in OR-steps and ensure correct auto-cancellation #9
* Move wiki comment validation from JS to Model Patch #3
* add my page blocks to track my wiki drafts or approval queue #4

## v0.9.0 (2026-02-14)

- First public release
- Save a wiki version as draft
- Start approval workflow with multiple steps
- Navigate first to the last approved/released version, required Permission “View wiki history”
- plugin configuration: per project or system-wide
- wiki content comment requirement on save if enabled
- support for Redmine 4.x, 5.x, and 6.x
- Activity view integration for approval status changes
- Email notifications for approval status updates