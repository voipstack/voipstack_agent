## Context

The capture functionality has been implemented to extract values from softswitch events and API responses. Currently, it captures the first matching event or response it receives. However, events like `OriginateResponse` can have different outcomes, and users need to conditionally capture only when specific conditions are met (e.g., only capture when Response is "Success").

## Goals / Non-Goals

**Goals:**
- Add conditional filtering to capture with `match` field
- Support AND logic for multiple conditions
- Work with both Asterisk (event-based) and FreeSWITCH (sync) patterns
- Maintain backward compatibility (match is optional)

**Non-Goals:**
- Complex query operators (OR, NOT, regex matching)
- Nested condition matching
- Dynamic condition evaluation

## Decisions

### Decision: AND logic for match conditions
**Rationale**: Simple and intuitive. All conditions must match for capture to proceed. This covers the primary use case of checking success status.

**Alternative considered**: OR logic - rejected as it's less common and can be confusing.

### Decision: `match.interface` structure
**Rationale**: Mirrors existing YAML structure patterns. The `interface` key contains key-value pairs to match against event/response fields.

**Example:**
```yaml
match:
  interface:
    Response: Success
    Reason: "4"
```

### Decision: Skip capture silently when no match
**Rationale**: This is conditional logic - if conditions aren't met, there's nothing to capture. Log at debug level for troubleshooting.

**Alternative considered**: Log error - rejected as non-matching conditions are expected behavior, not errors.

### Decision: Pass match conditions to SoftswitchState methods
**Rationale**: The softswitch implementations know the structure of events/responses and can best evaluate conditions.

**Signature change:**
```crystal
abstract def capture_event(event_name : String, command : String, interface : Hash(String, String), extract_field : String, match : Hash(String, String)? = nil) : String?
abstract def capture_api_response(command : String, interface : Hash(String, String), match : Hash(String, String)? = nil) : String?
```

## Risks / Trade-offs

**Risk**: Breaking change to SoftswitchState interface
→ **Mitigation**: Make match parameter optional with nil default

**Risk**: Performance impact when waiting for events with conditions
→ **Mitigation**: Conditions are checked as events arrive, not by polling

**Risk**: YAML structure confusion between `match.interface` and top-level `interface`
→ **Mitigation**: Clear documentation and examples showing `match.interface` is for filtering, `interface` is for command parameters

## Migration Plan

No migration needed - this is an additive change. Existing capture configurations without `match` continue to work.
