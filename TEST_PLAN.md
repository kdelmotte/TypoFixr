# Keyboard Hero - Test Plan (TDD)

This document defines acceptance criteria for all MVP features. Each test should pass before the feature is considered complete.

---

## 1. Text Capture Tests

### 1.1 Selected Text Priority
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-1.1.1 | Selected text is used when available | User selects "hello wrold" in a text field, presses shortcut | Only "hello wrold" is sent to API |
| TC-1.1.2 | Selection works across apps | Select text in Safari, Notes, Slack, Mail | Text captured correctly in each |
| TC-1.1.3 | Partial selection in long document | Select 3 words in a 10,000 word doc | Only selected 3 words sent |

### 1.2 Full Field Capture (No Selection)
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-1.2.1 | Short text field captured fully | Type "thansk" in empty Slack input, no selection | Full text "thansk" sent |
| TC-1.2.2 | Character limit respected | Type 600 chars, no selection, limit=500 | Prompt user to select text |
| TC-1.2.3 | Empty field handled | Press shortcut on empty field | Show "No text to fix" notification |

### 1.3 Correction Bookmark System
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-1.3.1 | Bookmark created after fix | Fix "helo" → "hello", type more | Bookmark stored at position 5 |
| TC-1.3.2 | Second fix uses bookmark | After TC-1.3.1, type "wrold", press shortcut | Only "wrold" sent (not "hello wrold") |
| TC-1.3.3 | Bookmark resets on field change | Fix text in Slack, switch to Mail | New field has no bookmark |
| TC-1.3.4 | Bookmark resets on app change | Fix in Notes, switch to Safari | Bookmark cleared |

### 1.4 Paragraph Fallback
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-1.4.1 | Current paragraph detected | Cursor in middle of paragraph, no selection | Current paragraph sent |
| TC-1.4.2 | Paragraph boundary = newline | Text has 3 paragraphs, cursor in 2nd | Only 2nd paragraph sent |

---

## 2. Text Replacement Tests

### 2.1 Basic Replacement
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-2.1.1 | Simple typo fix | "teh" | Replaced with "the" in place |
| TC-2.1.2 | Multiple typos | "teh qucik brwon fox" | "the quick brown fox" |
| TC-2.1.3 | Grammar fix | "i goes to store" | "I go to the store" (or similar) |
| TC-2.1.4 | Punctuation fix | "hello world how are you" | "Hello world, how are you?" |

### 2.2 Style Preservation
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-2.2.1 | Casual tone preserved | "yo whats up dude" | "Yo, what's up dude?" (not formal) |
| TC-2.2.2 | Abbreviations kept | "msg me asap pls" | "Msg me ASAP pls" (not expanded) |
| TC-2.2.3 | Intentional caps preserved | "THIS IS IMPORTANT" | Stays caps if intentional |
| TC-2.2.4 | Emoji preserved | "thanks 😊" | "Thanks 😊" |

### 2.3 Formatting Preservation
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-2.3.1 | Line breaks preserved | "line1\nline2\nline3" | Line breaks maintained |
| TC-2.3.2 | Indentation preserved | "  indented text" | Indentation maintained |
| TC-2.3.3 | Lists preserved | "- item1\n- item2" | List format maintained |

---

## 3. Undo/Revert Tests

### 3.1 Toggle Revert (3-second window)
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-3.1.1 | Revert within window | Fix text, press shortcut again in <3s | Original text restored |
| TC-3.1.2 | No revert after window | Fix text, wait 4s, press shortcut | New correction attempted |
| TC-3.1.3 | Toggle back and forth | Fix → revert → fix (all <3s) | Toggles correctly |

### 3.2 History-Based Revert
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-3.2.1 | History stores corrections | Make 3 corrections | All 3 appear in menu dropdown |
| TC-3.2.2 | Revert from history | Click revert on 2nd item | That specific text restored |
| TC-3.2.3 | History limit respected | Make 15 corrections | Only last 10 stored |
| TC-3.2.4 | History persists across sessions | Make corrections, quit, relaunch | History still visible |

### 3.3 System Undo Compatibility
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-3.3.1 | Cmd+Z works in Notes | Fix text in Notes, press Cmd+Z | Original restored |
| TC-3.3.2 | Cmd+Z works in Slack | Fix text in Slack, press Cmd+Z | Original restored |

---

## 4. Keyboard Shortcut Tests

### 4.1 Default Shortcut
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-4.1.1 | Default works | Press Cmd+Shift+. with text focused | Correction triggered |
| TC-4.1.2 | Works in any app | Test in Safari, Notes, Slack, Mail, VS Code | Works in all |
| TC-4.1.3 | No conflict with system | Press default shortcut | No system action triggered |

### 4.2 Custom Shortcut
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-4.2.1 | Can change shortcut | Set to Cmd+Shift+F in settings | New shortcut works |
| TC-4.2.2 | Old shortcut disabled | After changing, press old shortcut | Nothing happens |
| TC-4.2.3 | Invalid shortcut rejected | Try to set Cmd+C | Error: "This shortcut is reserved" |
| TC-4.2.4 | Shortcut persists | Change shortcut, quit, relaunch | Custom shortcut still active |

---

## 5. Menu Bar UI Tests

### 5.1 Icon States
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-5.1.1 | Idle state | App running, no activity | Static icon displayed |
| TC-5.1.2 | Loading state | Trigger correction | Spinner/animation shown |
| TC-5.1.3 | Error state | API fails | Error indicator on icon |
| TC-5.1.4 | Permission warning | No accessibility permission | Warning badge on icon |

### 5.2 Dropdown Menu
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-5.2.1 | Menu opens | Click menu bar icon | Dropdown appears |
| TC-5.2.2 | History displayed | Have 3 corrections | All 3 shown with original → fixed |
| TC-5.2.3 | History truncated | Correction with 200 chars | Shown truncated with "..." |
| TC-5.2.4 | Settings accessible | Click "Settings" | Settings window opens |
| TC-5.2.5 | Quit works | Click "Quit" | App terminates |

### 5.3 Settings Window
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-5.3.1 | Shortcut field works | Click and press new shortcut | Shortcut captured and saved |
| TC-5.3.2 | Character limit adjustable | Change from 500 to 1000 | New limit applied |
| TC-5.3.3 | Settings persist | Change settings, quit, relaunch | Settings retained |

---

## 6. OpenAI Integration Tests

### 6.1 API Communication
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-6.1.1 | Successful request | Valid text, API available | Corrected text returned |
| TC-6.1.2 | API key missing | No API key configured | Clear error message |
| TC-6.1.3 | API timeout | Simulate 10s delay | Timeout after 5s, error shown |
| TC-6.1.4 | Rate limit hit | Trigger rate limit | Friendly error, retry suggestion |

### 6.2 Response Speed
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-6.2.1 | Short text fast | "teh" (3 chars) | Response < 500ms |
| TC-6.2.2 | Medium text acceptable | 200 chars | Response < 1000ms |
| TC-6.2.3 | Max text within limit | 500 chars | Response < 2000ms |

### 6.3 Multi-language
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-6.3.1 | French | "je suis contant de te voir" | "Je suis content de te voir" |
| TC-6.3.2 | Spanish | "holla como estas" | "Hola, ¿cómo estás?" |
| TC-6.3.3 | German | "ich gehe nach hause" | Properly corrected German |
| TC-6.3.4 | Mixed language | "Hey, ça va bien?" | Both languages preserved |

---

## 7. SQLite Database Tests

### 7.1 Usage Logging
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-7.1.1 | Log created on correction | Make one correction | Row added with device_id, timestamp, tokens |
| TC-7.1.2 | Device ID consistent | Multiple corrections | Same device_id for all |
| TC-7.1.3 | Token count accurate | Fix "hello world" | Reasonable token count logged |
| TC-7.1.4 | Failed requests logged | API failure | Row added with success=false |

### 7.2 History Storage
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-7.2.1 | History saved | Make correction | Row in correction_history table |
| TC-7.2.2 | Original and fixed stored | Fix "teh" → "the" | Both values in row |
| TC-7.2.3 | Revert flag updated | Revert a correction | reverted=true in row |

### 7.3 Database Integrity
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-7.3.1 | DB created on first launch | Fresh install | Database file exists |
| TC-7.3.2 | DB survives app restart | Add data, quit, relaunch | Data still present |
| TC-7.3.3 | DB handles concurrent writes | Rapid corrections | No corruption or errors |

---

## 8. Accessibility Permission Tests

### 8.1 Permission Flow
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-8.1.1 | Permission prompt on launch | First launch, no permission | Onboarding window shown |
| TC-8.1.2 | Deep link works | Click "Open System Preferences" | Correct pane opens |
| TC-8.1.3 | Permission detected | Grant permission | App detects and shows success |
| TC-8.1.4 | Graceful without permission | Deny permission, try shortcut | Helpful error, link to settings |

### 8.2 Privacy Messaging
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-8.2.1 | Message clarity | Read onboarding text | Clear that it's user-triggered only |
| TC-8.2.2 | No storage mentioned | Read onboarding text | Clear that no text is stored |

---

## 9. Edge Case Tests

### 9.1 Error Handling
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-9.1.1 | API down | Disconnect network, trigger | "Couldn't connect" notification, text preserved |
| TC-9.1.2 | Read-only field | Focus read-only field, trigger | "This text field is read-only" notification |
| TC-9.1.3 | Unsupported app | App without accessibility support | "This app isn't supported" notification |
| TC-9.1.4 | Empty response from API | API returns empty string | Original text preserved, error logged |

### 9.2 Boundary Conditions
| ID | Test Case | Input | Expected Output |
|----|-----------|-------|-----------------|
| TC-9.2.1 | Very short text | "a" | Processed without error |
| TC-9.2.2 | Exactly at limit | 500 chars | Processed without prompt |
| TC-9.2.3 | Just over limit | 501 chars | Prompt to select text |
| TC-9.2.4 | Special characters | "hello @user #tag $100" | Special chars preserved |
| TC-9.2.5 | Unicode/emoji | "café ☕ naïve" | Unicode preserved correctly |

---

## 10. App Compatibility Tests

### 10.1 Native macOS Apps
| ID | Test Case | App | Expected Result |
|----|-----------|-----|-----------------|
| TC-10.1.1 | Notes | Apple Notes | Full functionality |
| TC-10.1.2 | Mail | Apple Mail | Full functionality |
| TC-10.1.3 | Messages | iMessage | Full functionality |
| TC-10.1.4 | TextEdit | TextEdit | Full functionality |

### 10.2 Third-Party Apps
| ID | Test Case | App | Expected Result |
|----|-----------|-----|-----------------|
| TC-10.2.1 | Slack | Slack desktop | Full functionality |
| TC-10.2.2 | VS Code | Visual Studio Code | Full functionality |
| TC-10.2.3 | Chrome | Google Chrome text fields | Full functionality |
| TC-10.2.4 | Safari | Safari text fields | Full functionality |
| TC-10.2.5 | Notion | Notion desktop | Test and document behavior |
| TC-10.2.6 | Google Docs | Chrome/Safari | Test and document behavior |

---

## Test Execution Checklist

### Pre-Release Checklist
- [ ] All TC-1.x (Text Capture) passing
- [ ] All TC-2.x (Text Replacement) passing
- [ ] All TC-3.x (Undo/Revert) passing
- [ ] All TC-4.x (Keyboard Shortcut) passing
- [ ] All TC-5.x (Menu Bar UI) passing
- [ ] All TC-6.x (OpenAI Integration) passing
- [ ] All TC-7.x (SQLite Database) passing
- [ ] All TC-8.x (Accessibility Permission) passing
- [ ] All TC-9.x (Edge Cases) passing
- [ ] All TC-10.x (App Compatibility) passing

### Known Limitations to Document
- [ ] Apps where functionality is limited
- [ ] Edge cases with unexpected behavior
- [ ] Performance characteristics

---

## Automated vs Manual Tests

### Automated (Unit/Integration Tests)
- TC-1.3.x (Bookmark system logic)
- TC-2.x (Text replacement logic - mock API)
- TC-3.1.x (Toggle timing logic)
- TC-6.2.x (Response timing)
- TC-7.x (Database operations)

### Manual Testing Required
- TC-1.1.x, TC-1.2.x (Cross-app text capture)
- TC-4.x (Global keyboard shortcuts)
- TC-5.x (UI visual verification)
- TC-8.x (System permission flow)
- TC-10.x (App compatibility)
