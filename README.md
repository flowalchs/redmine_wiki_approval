# Redmine Wiki Approval Plugin

[![build](https://github.com/flowalchs/redmine_wiki_approval/actions/workflows/build.yml/badge.svg)](https://github.com/flowalchs/redmine_wiki_approval/actions/workflows/build.yml)
[![Last release](https://img.shields.io/github/v/release/flowalchs/redmine_wiki_approval?label=latest%20release&logo=github&style=flat-square)](https://github.com/flowalchs/redmine_wiki_approval/releases/latest)
[![Rate at redmine.org](http://img.shields.io/badge/rate%20at-redmine.org-blue.svg?style=flat-square)](https://www.redmine.org/plugins/redmine_wiki_approval)
[![Redmine](https://img.shields.io/badge/redmine->=6.0-blue?logo=redmine&logoColor=%23B32024&labelColor=f0f0f0)](https://www.redmine.org)
[![codecov](https://codecov.io/gh/flowalchs/redmine_wiki_approval/graph/badge.svg?token=17Z5COBFM1)](https://codecov.io/gh/flowalchs/redmine_wiki_approval)
[![Wiki](https://img.shields.io/badge/wiki-home-lightgrey)](https://github.com/flowalchs/redmine_wiki_approval/wiki)
[![API Docs](https://img.shields.io/badge/API_Docs-Online-blue?style=flat-square&logo=swagger)](https://flowalchs.github.io/redmine_wiki_approval/)

This plugin adds an approval workflow to the wiki, allowing teams to review, approve, and control changes before they are published. It supports drafts, multi‑step approval processes, role‑based permissions, and status tracking to ensure content quality and traceability in collaborative documentation.

## 🧠 How it works

This plugin does **not** replace Redmine's wiki versioning, but optimizes it:

- **Smart Drafting**: Save your progress as a draft without creating a new Redmine wiki version. This keeps the history clean while you work.
- **Normal Versioning**: Once a change is finalized (or submitted), it is saved as a standard Redmine wiki version.
- **Privacy**: Drafts and unapproved changes remain private/hidden from regular viewers.
- **Approval Logic**: Only approved versions are displayed as the public wiki page.
- **Seamless Navigation**: Viewers are automatically redirected to the latest approved version.
- **Prerequisite**: Permission 'View wiki history' should be enabled for the redirection.

## 🌟 Features

- [**Draft-Based Editing**](https://github.com/flowalchs/redmine_wiki_approval/wiki/Page-Edit) – Work on changes without publishing them
- [**Multi-Step Approval Workflow**](https://github.com/flowalchs/redmine_wiki_approval/wiki/Approval-Workflow) – Configurable approval steps before publishing
- **Approval Activity View** – Track approval status by redmine activity feed
- **Role-Based Permissions** – Control who can draft, approve, or publish
- **REST API & OpenAPI Support** – Fully automate workflows with a modern REST API, including an interactive [OpenAPI Documentation](https://flowalchs.github.io/redmine_wiki_approval/)
- **Email Notifications** – Notifications for status and step changes
- [**Per‑Project or Global Settings**](https://github.com/flowalchs/redmine_wiki_approval/wiki/Settings) – Configure behavior globally or individually per project, such as enabling approval requirements, drafts, or mandatory comments.
- [**Mandatory Save Comment**](https://github.com/flowalchs/redmine_wiki_approval/wiki/Page-Edit) – Requires users to enter a comment when saving Wiki content (configurable on/off)
- [**My Page Blocks**](https://github.com/flowalchs/redmine_wiki_approval/wiki/My-Page) – Manage your Wiki Approval Queue for pending reviews and track your own Wiki Drafts directly from your personal dashboard
- [**Wiki Approval Macros**](https://github.com/flowalchs/redmine_wiki_approval/wiki/Macros) – Customizable wiki macros to display approval workflow information (status, users, steps, timestamps, diffs) directly inside wiki pages.
- [**Wiki Templates**](https://github.com/flowalchs/redmine_wiki_approval/wiki/Wiki-Templates) – Define reusable wiki page templates stored as regular wiki pages, organized by global scope, project, or role.
- [**Wiki List**](https://github.com/flowalchs/redmine_wiki_approval/wiki/Wiki-List) – Table view of all wiki pages across projects with filters, columns, sorting, grouping and saved queries, like the Redmine issue list.
- [**Wiki Comments**](https://github.com/flowalchs/redmine_wiki_approval/wiki/Wiki-Comments) – Inline comments on selected text and page comments, with replies, resolve/reopen per page version, activity and mail notifications.

## 🔐 Permissions Overview

| Permission           | Description                                       |
| -------------------- | ------------------------------------------------- |
| Manage Wiki approval | Configure workflow and settings                   |
| Start approval       | Begin approval workflow                           |
| Grant approval       | Approve a workflow step                           |
| Forward approval     | Move to another approver                          |
| View draft           | View unpublished versions                         |
| Publish wiki drafts  | Release an approved draft as the official version |
| Edit wiki templates  | Create and modify wiki template pages             |
| View wiki comments   | View inline and page comments                     |
| Add wiki comments    | Comment, reply, resolve; edit/delete own comments |
| Manage wiki comments | Edit and delete comments of other users           |

## 💡 Typical Use Case

1. Author creates or edits a wiki page as a draft
2. Changes are reviewed in one or more approval steps
3. Reviewers approve or reject the changes
4. Once approved, the page becomes publicly visible
5. Older versions remain accessible for audit and rollback

## 🌐 Internationalization
The plugin supports 14+ languages, including English, German, Japanese, French, Spanish, and more.
- <u>Full Support:</u> English and German are currently the primary maintained languages.
- <u>Experimental:</u> Other languages are currently in an experimental state.
- <u>Contribute:</u> Pull Requests to improve or add translations for your language are highly welcome!

## 📋 Requirements

- **Redmine**: 6.0 or higher
- **Ruby**: as required by your Redmine version (tested with 3.2 – 4.0)
- **Database**: MySQL or PostgreSQL
- **Rails**: Compatible with Redmine's Rails version

## 🚀 Installation

```bash
cd $REDMINE_ROOT/plugins
git clone https://github.com/flowalchs/redmine_wiki_approval.git
cd $REDMINE_ROOT
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```
Restart your Redmine server to load the plugin.
Enable the Module "Wiki approval" per project

## ⚙️ Plugin/Project Configuration

1. Configure the plugin under **Administration → Wiki approval** — each option can be enabled system-wide or made configurable per project
2. Enable the module **Wiki approval** in the project under **Project → Settings → Project → Modules**
3. Adjust the project-specific options under **Project → Settings → Wiki approval**

All options are described in the Wiki: [Settings](https://github.com/flowalchs/redmine_wiki_approval/wiki/Settings)

## 🖼️ Screenshots

Additional and up‑to‑date screenshots can be found in the Wiki:  
👉 **https://github.com/flowalchs/redmine_wiki_approval/wiki**

<p>
  <a href="https://github.com/flowalchs/redmine_wiki_approval/wiki/Approval-Workflow">
    <img
      src="https://github.com/flowalchs/redmine_wiki_approval/wiki/images/approval-workflow/grant-approval.png"
      alt="Wiki Screenshots Preview"
      width="100%"
    />
  </a>
</p>

## 🔄 Workflow Status Flow

The following diagram illustrates the lifecycle of a wiki page within the approval system:

```mermaid
graph TD
    %% Status Definitionen
    D(Draft)
    PEN(Pending)
    REJ(Rejected)
    CAN(Canceled)
    REL(Released)
    PUB(Published)

    %% Main
    D -- Start Approval --> PEN
    PEN -- Approve All --> REL
    PEN -- Decline --> REJ
    REJ -- Edit --> D
    
    %% direct
    D -- Direct Publish --> PUB

    %% canceled
    D & PEN & REJ -.->|New Version Started| CAN

    subgraph Approved_Versions [Viewers redirect versions]
        REL
        PUB
    end

    %% Styling
    style D fill:#fff4dd,stroke:#d4a017
    style REL fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style PUB fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style REJ fill:#ffebee,stroke:#c62828
    style CAN fill:#f5f5f5,stroke:#9e9e9e,stroke-dasharray: 5 5
```   

## ❌ Uninstall

```bash
cd $REDMINE_ROOT
bundle exec rake redmine:plugins:migrate NAME=redmine_wiki_approval VERSION=0 RAILS_ENV=production
```

## 🤝 Contributing
Pull requests, translations, and feedback are welcome.

## 📜 License
MIT License
