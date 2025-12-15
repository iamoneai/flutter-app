# User Module Documentation

## Overview

The User Module handles all end-user functionality including authentication, onboarding, settings management, category customization, and chat interactions. This document provides a comprehensive guide to the user-facing features and their underlying architecture.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Authentication Flow](#authentication-flow)
3. [User Onboarding](#user-onboarding)
4. [Firebase Data Structure](#firebase-data-structure)
5. [User Settings System](#user-settings-system)
6. [Category Management](#category-management)
7. [Services Reference](#services-reference)
8. [Screens Reference](#screens-reference)
9. [Security Rules](#security-rules)

---

## Architecture Overview

### File Structure

```
lib/user/
├── screens/
│   ├── user_auth_wrapper.dart      # Auth state management
│   ├── user_login_screen.dart      # Login UI
│   ├── user_registration_screen.dart # Registration UI
│   ├── user_dashboard.dart         # Main dashboard with navigation
│   ├── user_chat_screen.dart       # Chat interface
│   ├── user_settings_screen.dart   # Settings with 4 tabs
│   ├── memories_screen.dart        # Memory management
│   └── profile_screen.dart         # User profile
├── services/
│   ├── user_auth_service.dart      # Authentication operations
│   ├── user_onboarding_service.dart # New user initialization
│   └── user_settings_service.dart  # Settings & categories CRUD
└── widgets/
    ├── create_category_dialog.dart # Create custom category
    └── edit_category_dialog.dart   # Edit/customize category
```

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER REGISTRATION                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. User submits registration form                               │
│              ↓                                                   │
│  2. Firebase Auth creates account                                │
│              ↓                                                   │
│  3. Cloud Function generates IIN (or local fallback)             │
│              ↓                                                   │
│  4. UserOnboardingService.initializeNewUser()                    │
│              ↓                                                   │
│     ┌───────┴───────┐                                           │
│     ↓               ↓                                           │
│  Create User     Copy Admin Data                                 │
│  Profile         ├── Categories → users/{uid}/categories/       │
│                  └── Settings   → users/{uid}/settings/          │
│              ↓                                                   │
│  5. User redirected to Dashboard                                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Authentication Flow

### Login Process

```dart
// Location: lib/user/services/user_auth_service.dart

1. User enters email/password
2. FirebaseAuth.signInWithEmailAndPassword()
3. UserAuthWrapper detects auth state change
4. ensureUserOnboarded() checks/creates user data
5. Redirect to UserDashboard
```

### Registration Process

```dart
// Location: lib/user/screens/user_registration_screen.dart

1. User fills registration form (firstName, lastName, email, password)
2. Form validation (password strength, email format)
3. FirebaseAuth.createUserWithEmailAndPassword()
4. Cloud Function 'registerUser' generates IIN
5. UserOnboardingService.initializeNewUser() called
6. Success dialog shows IIN
7. Redirect to Dashboard
```

### Auth Wrapper Logic

```dart
// Location: lib/user/screens/user_auth_wrapper.dart

StreamBuilder(FirebaseAuth.authStateChanges()) {
  if (not authenticated) → UserLoginScreen
  if (authenticated) {
    await ensureUserOnboarded(uid)  // Auto-onboard if needed
    if (has IIN) → UserDashboard
    else → UserLoginScreen
  }
}
```

---

## User Onboarding

### Purpose

When a new user registers, the onboarding service:
1. Creates their user profile document
2. Copies all admin-defined categories to their personal collection
3. Copies admin global settings as their default preferences

### Onboarding Service Methods

| Method | Description |
|--------|-------------|
| `initializeNewUser()` | Full onboarding for new registrations |
| `isUserOnboarded()` | Check if user has been onboarded |
| `onboardExistingUser()` | Onboard users who missed initial setup |

### Default Categories (Fallback)

If no admin categories exist, these defaults are created:

| Category | Primary LLM | Fallback LLM | Priority |
|----------|-------------|--------------|----------|
| General | gemini-flash | gpt-4o-mini | LOW |
| Code & Programming | claude-haiku | gpt-4o-mini | HIGH |
| Creative Writing | gpt-4o-mini | claude-haiku | MEDIUM |

---

## Firebase Data Structure

### User Profile

```
Collection: users/{uid}
Document Fields:
├── displayName: string      # "John Doe"
├── email: string            # "john@example.com"
├── firstName: string        # "John"
├── lastName: string         # "Doe"
├── iin: string              # "24AB-1234-5678-WXYZ"
├── role: string             # "user"
├── status: string           # "ACTIVE"
├── onboarded: boolean       # true
├── createdAt: timestamp
└── updatedAt: timestamp
```

### User Settings

```
Document: users/{uid}/settings/preferences
Fields:
├── Chat Preferences
│   ├── defaultContext: string       # "personal" | "work" | "family"
│   ├── responseStyle: string        # "brief" | "balanced" | "detailed"
│   ├── personalityTone: string      # "professional" | "friendly" | "casual"
│   ├── memoryEnabled: boolean       # true
│   ├── autoMemorySave: boolean      # true
│   ├── maxTokens: number            # 1024
│   ├── temperature: number          # 0.7
│   └── emojiUsage: string           # "none" | "minimal" | "moderate" | "frequent"
│
├── LLM Preferences
│   ├── defaultLlm: string           # "gemini-flash"
│   ├── fallbackLlm: string          # "gpt-4o-mini"
│   ├── useOwnKeys: boolean          # false
│   ├── openaiKey: string | null
│   ├── anthropicKey: string | null
│   └── googleKey: string | null
│
├── Privacy Settings
│   ├── memoryRetentionDays: number  # 7 | 30 | 90 | 365 | -1 (forever)
│   └── autoDeleteHistory: boolean   # false
│
├── Locale Settings
│   ├── dateFormat: string           # "MM/DD/YYYY"
│   ├── timeFormat: string           # "12h" | "24h"
│   └── timezone: string             # "UTC"
│
└── Metadata
    ├── createdAt: timestamp
    └── updatedAt: timestamp
```

### User Categories

```
Collection: users/{uid}/categories/{categoryId}
Document Fields:
├── name: string              # "Code & Programming"
├── description: string       # "Programming questions"
├── keywords: array<string>   # ["python", "javascript", "code"]
├── primaryLlm: string        # "claude-haiku"
├── fallbackLlm: string       # "gpt-4o-mini"
├── priority: string          # "HIGH" | "MEDIUM" | "LOW"
├── type: string              # "inherited" | "modified" | "custom"
├── sourceAdminId: string     # Original admin category ID (null for custom)
├── isActive: boolean         # true
├── contextFilter: string     # "all" | "personal" | "work" | "family"
├── createdAt: timestamp
└── updatedAt: timestamp
```

### Category Types Explained

| Type | Badge Color | Description | User Actions |
|------|-------------|-------------|--------------|
| `inherited` | Gray (DEFAULT) | Unmodified copy from admin | Enable/Disable, Customize |
| `modified` | Orange (MODIFIED) | Admin category user has edited | Edit, Reset to Default, Enable/Disable |
| `custom` | Blue (CUSTOM) | User-created category | Full control (Edit, Delete) |

---

## User Settings System

### Settings Screen Tabs

#### Tab 1: Categories
- View all categories grouped by type
- Create new custom categories
- Edit/customize existing categories
- Reset modified categories to admin defaults
- Enable/disable categories
- Sync new admin categories

#### Tab 2: Chat Preferences
- Default context (Personal/Work/Family)
- Response style (Brief/Balanced/Detailed)
- Personality tone (Professional/Friendly/Casual)
- Emoji usage level
- Memory retrieval toggle
- Auto-save memories toggle
- Max tokens slider (256-4096)
- Temperature/creativity slider (0.0-1.0)

#### Tab 3: LLM Preferences
- Default LLM provider selection
- Fallback LLM provider selection
- "Bring Your Own Keys" section:
  - Toggle to use personal API keys
  - OpenAI API key input
  - Anthropic API key input
  - Google AI API key input

#### Tab 4: Privacy & Data
- Memory retention period (7 days to Forever)
- Auto-delete chat history toggle
- Export My Data button (JSON to clipboard)
- Delete All My Data button (with confirmation)

---

## Category Management

### Creating Custom Categories

```dart
// User creates category via CreateCategoryDialog
{
  name: "My Custom Topic",
  description: "Description here",
  keywords: ["keyword1", "keyword2"],
  primaryLlm: "gemini-flash",
  fallbackLlm: "gpt-4o-mini",
  priority: "MEDIUM",
  contextFilter: "all",
  type: "custom",           // Always "custom" for user-created
  sourceAdminId: null       // No admin source
}
```

### Editing Categories

When editing an `inherited` category:
1. Warning banner shown: "Editing will mark this as customized"
2. Original admin values shown in collapsible section
3. On save, `type` changes from `inherited` → `modified`

### Resetting to Default

For `modified` categories with `sourceAdminId`:
1. Fetch original admin category data
2. Overwrite user's category with admin values
3. Change `type` back to `inherited`

### Syncing Admin Updates

```dart
// Check for new admin categories user doesn't have
checkAdminUpdates(uid) {
  1. Get all user categories' sourceAdminId values
  2. Get all admin categories
  3. Find admin categories not in user's sourceAdminId set
  4. Return list of new categories available
}

// User selects which to add via dialog
syncNewAdminCategories(uid, selectedAdminIds) {
  For each selected admin category:
    Copy to users/{uid}/categories/ with type: "inherited"
}
```

### Category Priority for Smart Router

Categories are sorted for routing in this order:
1. **Type**: custom → modified → inherited
2. **Priority**: HIGH → MEDIUM → LOW

```dart
getEffectiveCategories(uid) {
  // Returns only active categories, sorted for routing
  // Custom categories take precedence over defaults
}
```

---

## Services Reference

### UserAuthService

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `signInWithEmail` | email, password | UserCredential | Sign in existing user |
| `registerUser` | email, password, firstName, lastName | {user, iin} | Register new user with onboarding |
| `signOut` | - | void | Sign out current user |
| `getUserProfile` | uid | Map? | Get user's Firestore profile |
| `hasCompletedRegistration` | uid | bool | Check if user has IIN |
| `ensureUserOnboarded` | uid | void | Onboard if not already done |
| `sendPasswordResetEmail` | email | void | Send password reset |

### UserOnboardingService

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `initializeNewUser` | uid, displayName, email, iin, firstName?, lastName? | void | Full new user setup |
| `isUserOnboarded` | uid | bool | Check onboarding status |
| `onboardExistingUser` | uid | void | Onboard existing user |

### UserSettingsService

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getUserSettings` | uid | Map? | Get user settings |
| `getUserSettingsStream` | uid | Stream<Map?> | Real-time settings stream |
| `saveUserSettings` | uid, settings | void | Save all settings |
| `updateUserSettings` | uid, updates | void | Partial update |
| `getUserCategoriesStream` | uid | Stream<List<Map>> | Real-time categories |
| `getUserCategories` | uid | List<Map> | Get all categories |
| `createCategory` | uid, category | String (id) | Create custom category |
| `updateCategory` | uid, categoryId, data, wasInherited? | void | Update category |
| `deleteCategory` | uid, categoryId | void | Delete category |
| `toggleCategory` | uid, categoryId, isActive | void | Enable/disable |
| `resetCategoryToDefault` | uid, categoryId, sourceAdminId | void | Reset to admin default |
| `getAdminCategory` | adminCategoryId | Map? | Get original admin data |
| `checkAdminUpdates` | uid | Map | Check for new admin categories |
| `syncNewAdminCategories` | uid, adminCategoryIds | void | Add new admin categories |
| `getEffectiveCategories` | uid | List<Map> | Get sorted active categories |
| `exportUserData` | uid | Map | Export all user data |
| `deleteAllUserData` | uid | void | Delete everything |
| `getAvailableLlms` | - | List<Map> | Get LLM options list |

---

## Screens Reference

### Navigation Flow

```
App Launch
    ↓
UserAuthWrapper
    ├── Not Authenticated → UserLoginScreen
    │                           ├── Login → Dashboard
    │                           └── Register → UserRegistrationScreen → Dashboard
    │
    └── Authenticated → UserDashboard
                            ├── Tab 0: UserChatScreen
                            ├── Tab 1: MemoriesScreen
                            ├── Tab 2: ProfileScreen
                            └── Menu → UserSettingsScreen
```

### Route Definitions

| Route | Screen | Description |
|-------|--------|-------------|
| `/` | UserAuthWrapper | Entry point, handles auth state |
| `/user` | UserAuthWrapper | Alias for root |
| `/user/login` | UserLoginScreen | Direct login access |
| `/user/register` | UserRegistrationScreen | Direct registration access |
| `/user/home` | UserDashboard | Direct dashboard access |
| `/user/settings` | UserSettingsScreen | Settings screen |

---

## Security Rules

### Firestore Rules Summary

```javascript
// Admin config - users can READ for onboarding copy
match /admin/config/{document=**} {
  allow read: if authenticated;
  allow write: if superAdmin;
}

// User data - users can only access their own
match /users/{userId}/{document=**} {
  allow read, write: if request.auth.uid == userId;
}
```

### Key Security Principles

1. **User Isolation**: Users can only read/write their own data
2. **Admin Read Access**: Users can read admin config (for onboarding)
3. **Admin Write Protection**: Only super admins can modify admin config
4. **No Cross-User Access**: No user can access another user's data

---

## Available LLM Options

| ID | Display Name | Provider |
|----|--------------|----------|
| claude-haiku | Claude Haiku | Anthropic |
| claude-sonnet | Claude Sonnet | Anthropic |
| gpt-4o-mini | GPT-4o Mini | OpenAI |
| gpt-4o | GPT-4o | OpenAI |
| gemini-flash | Gemini Flash | Google |
| gemini-pro | Gemini Pro | Google |

---

## UI Color Scheme

| Element | Color Code | Usage |
|---------|------------|-------|
| Background | #0f0f1a | Main background |
| Card/Container | #1a1a2e | Cards, dialogs |
| Border | #2a2a3e | Subtle borders |
| Primary Accent | #7c3aed | Buttons, highlights |
| Secondary Accent | #6366f1 | Keywords, info |
| Claude Provider | Purple | Provider indicator |
| OpenAI Provider | Green | Provider indicator |
| Gemini Provider | Blue | Provider indicator |
| HIGH Priority | Green | Priority badge |
| MEDIUM Priority | Yellow | Priority badge |
| LOW Priority | Gray | Priority badge |
| CUSTOM Badge | Blue | Category type |
| MODIFIED Badge | Orange | Category type |
| DEFAULT Badge | Gray | Category type |

---

## Error Handling

### Common Error Scenarios

| Scenario | Handling |
|----------|----------|
| No admin categories | Default categories created automatically |
| No admin settings | Default settings created automatically |
| Network error loading | SnackBar error message, retry option |
| Save failure | SnackBar error with details |
| Category delete (non-custom) | Operation blocked, only custom deletable |
| Reset without sourceAdminId | Operation blocked |

---

## Future Considerations

1. **Offline Support**: Consider caching categories/settings locally
2. **Category Sharing**: Allow users to share custom categories
3. **Import/Export Categories**: JSON import/export for categories
4. **Category Templates**: Pre-built category packs users can install
5. **Usage Analytics**: Track which categories are most used
6. **A/B Testing**: Test different default configurations

---

*Last Updated: December 2024*
*Version: 1.0*
