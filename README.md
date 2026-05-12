# Redmine Wiki Approval Plugin

[![build](https://github.com/FloWalchs/redmine_wiki_approval/actions/workflows/build.yml/badge.svg)](https://github.com/FloWalchs/redmine_wiki_approval/actions/workflows/build.yml)
[![Last release](https://img.shields.io/github/v/release/FloWalchs/redmine_wiki_approval?label=latest%20release&logo=github&style=flat-square)](https://github.com/FloWalchs/redmine_wiki_approval/releases/latest)
[![Rate at redmine.org](http://img.shields.io/badge/rate%20at-redmine.org-blue.svg?style=flat-square)](https://www.redmine.org/plugins/redmine_wiki_approval)
[![Redmine](https://img.shields.io/badge/redmine->=4.2-blue?logo=redmine&logoColor=%23B32024&labelColor=f0f0f0)](https://www.redmine.org)
[![codecov](https://codecov.io/gh/FloWalchs/redmine_wiki_approval/graph/badge.svg?token=17Z5COBFM1)](https://codecov.io/gh/FloWalchs/redmine_wiki_approval)
[![Wiki](https://img.shields.io/badge/wiki-home-lightgrey)](https://github.com/FloWalchs/redmine_wiki_approval/wiki)
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

- **Draft-Based Editing** – Work on changes without publishing them
- **Multi-Step Approval Workflow** – Configurable approval steps before publishing
- **Approval Activity View** – Track approval status by redmine activity feed
- **Role-Based Permissions** – Control who can draft, approve, or publish
- **REST API & OpenAPI Support** – Fully automate workflows with a modern REST API, including an interactive [OpenAPI Documentation](https://flowalchs.github.io/redmine_wiki_approval/)
- **Email Notifications** – Notifications for status and step changes
- **Per‑Project or Global Settings** – Configure behavior globally or individually per project, such as enabling approval requirements, drafts, or mandatory comments.
- **Mandatory Save Comment** – Requires users to enter a comment when saving Wiki content (configurable on/off)
- **My Page Blocks** – Manage your Wiki Approval Queue for pending reviews and track your own Wiki Drafts directly from your personal dashboard
- **Wiki Approval Macros** – Customizable wiki macros to display approval workflow information (status, users, steps, timestamps, diffs) directly inside wiki pages.

## 🔐 Permissions Overview

| Permission           | Description                                       |
| -------------------- | ------------------------------------------------- |
| Manage Wiki approval | Configure workflow and settings                   |
| Start approval       | Begin approval workflow                           |
| Grant approval       | Approve a workflow step                           |
| Forward approval     | Move to another approver                          |
| View draft           | View unpublished versions                         |
| Publish wiki drafts  | Release an approved draft as the official version |

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

- **Redmine**: 4.2 or higher
- **Ruby**: 2.7 or higher
- **Rails**: Compatible with Redmine's Rails version

## 🚀 Installation

```bash
cd $REDMINE_ROOT/plugins
git clone https://github.com/FloWalchs/redmine_wiki_approval.git
cd $REDMINE_ROOT
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```
Restart your Redmine server to load the plugin.
Enable the Module "Wiki approval" per project

## ⚙️ Plugin/Project Configuration

1. Navigate to **Administation → Wiki approval**
   - Settings can be configured per project or system-wide
2. Navigate to **Project Settings → Wiki approval**
   - enable the modul per project
3. Available options:
   - Settings 
     - Wiki comment required 
     - Wiki Content Drafts enabled
   - Approval workflow
     - Wiki draft enabled
     - Wiki approval enabled
       - Approval required
       - Approval workflow for next version (required)

## 🖼️ Screenshots

Additional and up‑to‑date screenshots can be found in the Wiki:  
👉 **https://github.com/FloWalchs/redmine_wiki_approval/wiki/Screenshots**

<p>
  <a href="https://github.com/FloWalchs/redmine_wiki_approval/wiki/Screenshots">
    <img
      src="https://github.com/user-attachments/assets/bd26ea3b-a358-4c3e-98fc-3dc497b39037"
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

## 🧩 Macros

The following macros can be used inside wiki pages to render approval-related information directly within the content:

```textile
{{rwa_status}}                # Display the current approval status as a badge
{{rwa_status(text)}}          # Display the approval status as plain text

{{rwa_revision}}              # Display the approved revision number

{{rwa_updated_at}}            # Display last workflow update timestamp
{{rwa_updated_at(relative)}}  # Display relative update time (e.g. "about 1 minute ago")

{{rwa_diff}}   # Display a diff link between the current wiki version and the last approved version

{{rwa_users}}                  # Display all users involved in the approval workflow
{{rwa_users(step=1)}}          # Display only the users assigned to approval step 1
{{rwa_users(step=1,approved)}} # Display only the users assigned to approval step 1 that are already approved

#Display the workflow starter with avatar, profile link, and additional details via mouse‑over
{{rwa_users(starter,userimage,mouseover,userlink)}} 

# Display only the user who initiated the approval workflow
{{rwa_users(starter,step=0)}} 

# Display approvers of step 2 including approval notes and current step status
{{rwa_users(step=2,note,status)}} 
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
