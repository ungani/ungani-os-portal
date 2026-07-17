# UNGANI OS — FINAL UI/UX MASTER SPECIFICATION (VERSION 1)

## PROJECT GOAL

UNGANI OS is **NOT** a traditional ERP.

UNGANI OS is a **Business Command Center** designed to allow a business owner, manager or CEO to understand their entire business within **5 seconds** after opening the dashboard.

The system must feel:

* Modern
* Premium
* Fast
* Clean
* Intelligent
* Minimal
* Professional

The goal is **less clicking, less searching, more understanding.**

The design should always answer three questions:

1. What needs my attention right now?
2. Is my business healthy?
3. What should I do next?

The interface should never feel crowded.

Whenever possible, place information inside dedicated pages instead of the dashboard.

The dashboard is a summary.

---

# DESIGN PRINCIPLES

Every page should follow these principles.

- Plenty of spacing.
- Large readable headings.
- Rounded cards.
- Soft shadows.
- Smooth hover animations.
- Clickable cards.
- Animated transitions.
- Consistent spacing.
- Same border radius everywhere.
- Same card height wherever possible.
- Maximum readability.

Do NOT redesign the current color scheme.

Maintain the existing UNGANI branding.

---

# GLOBAL TOP BAR

Keep the current top bar.

Order:

Search

Notifications

Messages

AI Assistant

Quick Create

Profile

Do not overcrowd this section.

Search should search EVERYTHING inside the business.

---

# SIDEBAR DESIGN

The sidebar should remain simple.

Group related items together.

Avoid extremely long menus.

Collapse sections when possible.

Each category should have a separator title.

Example:

MAIN

OPERATIONS

BUSINESS

SUPPORT

ACCOUNT

SYSTEM

Icons should remain consistent throughout the application.

---

# ADMIN SIDEBAR

MAIN

- Dashboard
- Business Health
- Today's Activity

OPERATIONS

- Client Registrations
- Client Profiles
- Users & Permissions
- Tasks
- Calendar

BUSINESS

- Money Records
- Assets
- Documents
- Reports
- System Analytics

SUPPORT

- Support Desk
- Client Chat
- Notifications

ACCOUNT

- Billing
- Packages
- Settings

SYSTEM

- Global Controls
- Automation Rules
- AI Settings
- System Health
- Audit Logs
- Logout

---

# ADMIN DASHBOARD

The dashboard should remain a summary only.

The order should be:

1. **Greeting** — Good Morning / Welcome / short summary / Today's AI Brief

2. **Business Health Score** — Already implemented. Improve it. The Health Score should calculate: Revenue, Expenses, Cash Flow, Outstanding Payments, Inventory, Support Issues, Overdue Tasks, Staff Activity, Business Growth. Show: Overall Score, Trend, Recommendation.
   Example:
   > Business Health 92% — Excellent
   > Recommendation: Outstanding invoices are low. Cash flow healthy. Fuel costs increased by 12%. Review expenses.

3. **Today's Attention** — Notifications, Approvals, Support, Urgent Tasks, System Warnings. Keep this compact.

4. **Quick Actions** — Approve Client, Create User, View Reports, Support Desk, Billing, Settings.

5. **Platform Statistics** — Active Businesses, Users, Assets, Monthly Revenue, Transactions, Support Tickets.

6. **Recent Activity Timeline** — Newest activity first. Live updates.
   Example:
   > 09:30 Client registered
   > 09:45 Payment received
   > 10:02 Support ticket created
   > 10:30 Report exported

7. **Recent Registrations** — Compact table.

8. **Support Overview** — Open, Pending, Resolved.

9. **System Health** — Database, Storage, API, Emails, Notifications, Background Jobs. Everything displayed using simple status indicators.

10. **Footer** — Version, Support, Copyright.

---

# CLIENT SIDEBAR

MAIN

- Dashboard
- Business Health
- Money
- Tasks
- Calendar

BUSINESS

- Overview
- Operations
- People
- Assets
- Inventory
- Documents
- Reports
- Customers

SUPPORT

- Admin Chat
- Team Chat
- Support
- Notifications

ACCOUNT

- Onboarding
- Subscription
- Billing
- Settings
- Account Status
- Light/Dark Mode
- Logout

---

# CLIENT DASHBOARD

The dashboard should answer:

- What is happening?
- What needs attention?
- What should I do next?

Order:

1. **Greeting** — Business Name, Welcome, AI Summary

2. **Business Health Score** — Overall, Trend, Recommendation

3. **Today's Attention** — Outstanding Payments, Maintenance, Tasks, Bookings, Approvals

4. **Quick Actions** — Should remain visible. Examples: New Sale, New Expense, Add Customer, Upload Document, Assign Task, Record Payment

5. **Business Snapshot** — Revenue, Expenses, Profit, Balance, Cash Flow, Pending Payments

6. **Recent Activity** — Timeline

7. **Section Comparison** — Charts

8. **Upcoming Calendar**

9. **Support**

10. **Footer**

---

# BUSINESS HEALTH SCORE

Already implemented.

Improve it by including:

- Revenue Trend
- Expense Trend
- Cash Flow
- Pending Tasks
- Overdue Payments
- Inventory Status
- Customer Satisfaction
- Support Performance
- Employee Activity
- Business Growth

Instead of only displaying a score, also display: Strengths, Weaknesses, Recommendations.

---

# EVERY PAGE LAYOUT

Every page should follow exactly the same structure.

- HEADER — Large title, small description, Quick Actions
- Summary Cards
- Filters
- Main Content — Table or Cards
- Footer

Consistency is extremely important.

---

# TABLE DESIGN

Every page that contains records should follow this layout.

**Top Section**
- Page Title
- Description
- Quick Actions
- Statistics Cards

**Below that**
- Search
- Date Filter
- Status Filter
- Business Filter
- Export
- Refresh

**Below that**
- Table — Columns, Clickable rows, Hover effect
- Right side — Three-dot action menu: View, Edit, Duplicate, Archive, Delete
- Pagination at the bottom.

---

# DOCUMENTS PAGE

**Top** — Summary Cards: Total Documents, Pending, Approved, Archived, Storage Used

**Then** — Search, Category, Owner, Department, Date, Status, Upload Button

**Then** — Document List. Each row should contain: Icon, Title, Category, Owner, Last Updated, Status, Actions.

Clicking a document opens a detailed side panel instead of navigating away immediately, allowing users to preview information quickly while staying on the same page.

---

# MONEY PAGE

- Summary Cards — Income, Expenses, Profit, Cash Flow, Outstanding
- Filters
- Transactions — Search, Export
- Charts
- Recent Activity

---

# REPORTS PAGE

- Summary
- Saved Reports
- Generate Report
- Filters
- Charts
- Tables
- Download
- Schedule Report

---

# AI FEATURES

The AI Assistant should not only answer questions. It should also proactively provide:

- Morning Brief
- Business Summary
- Recommendations
- Cost Saving Suggestions
- Growth Opportunities
- Warnings
- Automation Suggestions

Examples:

- "You have five overdue invoices."
- "Fuel costs increased this month."
- "Three employees have unfinished tasks."
- "This branch is outperforming the others."

---

# SMART AUTOMATION

Allow users to create automation rules.

Examples:

- If payment becomes overdue → Send reminder.
- If inventory reaches minimum → Notify manager.
- If trip completed → Generate invoice.
- If support ticket closed → Notify client.

---

# PREMIUM UX FEATURES

Add:

- Global Search
- Favorites
- Pinned Records
- Recently Visited
- Keyboard Shortcuts
- Command Palette (Ctrl/⌘ + K)
- Floating Quick Create Button
- Activity Timeline
- Watch List
- Smart Notifications
- Smart Empty States
- Saved Views
- Workspace Switcher (for businesses managing multiple companies or branches)

---

# USER EXPERIENCE RULES

- Never overload the dashboard.
- Every card must have a purpose.
- Every click should feel fast.
- Every page should look familiar.
- Maintain consistent spacing.
- Use animations sparingly to reinforce interactions, not distract from them.
- Always prioritize readability over visual effects.
- Important actions should never require more than three clicks.
- The dashboard is a command center, not a reporting page.
- Detailed information belongs inside dedicated modules.

---

# FINAL DESIGN GOAL

The finished UNGANI OS should feel like a premium Business Operating System that gives business owners complete clarity and confidence. A CEO should be able to log in, understand the health of the business within seconds, identify what requires attention, and take action without searching through multiple screens. Every module should feel connected, every page should follow the same design language, and the overall experience should remain simple, fast, intelligent, and scalable for businesses of every size—from a small retail shop to a logistics company, warehouse, hotel, property manager, clinic, or multi-branch enterprise.

This specification should be treated as the master UI/UX standard. New features should follow these principles instead of introducing new layouts or inconsistent navigation.
