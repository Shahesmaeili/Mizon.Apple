# Controller parity on Apple

Apple owner: Apple client chat. Initial Apple base: 82593334f380f6ab84ad8d3baf001592ca4c263d.
Integrated Apple deep-link base: 900540c48af5214635d2bfc82bd5327134cce56a.
Windows behavior reference: a7010d7a0e67e8f31e68712d5fb2314a599b53aa.
Windows machine-readable fixture: 55d0f5ee21d255515871cb11b7c09bcd603e362e,
\`docs/ai/contracts/auth-gamepad-v1.json\`, copied byte-for-byte into \`Tests/Fixtures\`.
The Apple SDK, server, database and session data require no changes.

| Surface | Apple behavior |
| --- | --- |
| Login and registration | Physical directional input and repeat, independent controller focus, form controls, validated submit, bounded auth feedback, and a localized controller keyboard. Identifier, email and username share the native field filters. Password editing stays masked and edits the end, with the form's explicit reveal command available outside the keyboard. |
| Welcome | Help, retry or return to sign-in when the error actions are available, focus shortcuts, and scroll. |
| Music Home and header | Focus and activation for available controls, scroll, play from playlist, and back to the nearest supported surface. Sections presented by the header as unavailable are skipped. |
| Search and story | Search result navigation and a controller keyboard. A linked search or story above a detail page preserves the navigation stack and suspends the underlying controller owner. |
| Music, video, person, and story details | Focus available actions, native playback, following and reactions, scroll, return, and widget music links. |
| Playlist, library and activity | Focus and activate actionable controls or rows, independently scroll the list, and return. macOS retains native context menus and allows direct controller play/copy shortcuts where applicable. |
| Mood, nearby devices, settings and preview | Controller ownership separate from Music Home. Uses the existing surface actions. Native file picker, native system menus, AppKit window chrome, and secondary preview controls such as the scrubber still use their platform interaction. |
| Apple Watch | Watch surfaces retain native touch and Digital Crown navigation. The watchOS SDK has no GameController module or extended controller profile. |

The sampler keeps the existing controller while connected, drops input on surface changes, and primes the first sample for every controller and surface. Xbox and Share are left to the OS. No button actions or auth input are exposed through MCP. Apple currently has no live MCP host or scoped authentication adapter.

Verification uses the production input reducer and session, the exact Windows vectors, and tests for controller keyboard edits, masked input, controller changes, held actions and modal reentry. Application builds verify compiler and linker coverage. Physical controller input, motors, screen-reader output, visual focus, and device rotation require device-level verification.
