# Services/

## OVERVIEW
Meeting service integration and AppleScript automation.

## FILES
| File | Lines | Role |
|------|-------|------|
| MeetingServices.swift | ~28k | 50+ meeting service URL patterns, link detection, join URL generation |
| Scripts.swift | ~5k | AppleScript execution for event automation |

## MEETING SERVICES
MeetingServices.swift is the largest file. It contains:
- `MeetingServiceType` enum with all supported services
- URL pattern matching for detecting meeting links
- `getMeetingLink()` - extracts join URL from event notes/URL
- `createMeetingService()` - factory for service instances
- `joinMeeting()` - opens meeting link in browser/app

## APPLEE SCRIPT
Scripts.swift handles external app automation via NSAppleScript.
