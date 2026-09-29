# Local Transfer

A peer-to-peer tool for moving text, files, and clipboard content between
devices on a local network. No server, no account, no cloud.

## Language

### Devices and identity

**Device**:
One installed instance of the app, running on one machine. A person with a
phone and a laptop owns two Devices.
_Avoid_: Client, Peer, Node, Endpoint, 客户端

**Alias**:
The human-readable name a Device shows to other Devices.
_Avoid_: Name, Hostname, DisplayName, Nickname

**Fingerprint**:
The stable identity of a Device, which lets other Devices tell it apart, avoid
discovering themselves, and recognise it again after a restart.
_Avoid_: ID, DeviceId, UUID, Token, Key

**Owner**:
The person a Device belongs to. An Owner is established by a key pair that
never leaves the Device.
_Avoid_: User, Account, Me, Identity, 用户

**Owner Group**:
The set of Devices that share an Owner. Clipboard Mirroring happens only
within an Owner Group.
_Avoid_: My Devices, Trusted Group, Family, Team, 我的设备

**Pairing**:
The one-time act of admitting a Device into an Owner Group.
_Avoid_: Linking, Binding, Registration, Handshake, 配对

**Favorite**:
A Device the user has marked as trusted, so Transfers with it can skip
per-transfer confirmation. Being a Favorite is **not** membership of an Owner
Group, and confers no clipboard access.
_Avoid_: Paired, Trusted, Friend, Contact, Saved

### Finding each other

**Discovery**:
The process by which a Device learns which other Devices are currently
Reachable.
_Avoid_: Scan, Search, Sync, Browse, 搜索

**Announcement**:
The message a Device broadcasts to make itself discoverable.
_Avoid_: Beacon, Advertise, Broadcast, Ping

**Reachable**:
A Device that Discovery has found and that can currently accept a Transfer.
_Avoid_: Online, Available, Nearby, Visible, Connected

**Manual Address**:
An address the user types in to reach a Device that Discovery could not find.
_Avoid_: Direct IP, Custom Target, Hardcoded

**Known Device**:
A Device this Device has transferred with before, remembered so it can be
reached again without Discovery.
_Avoid_: Recent, History, Cached, Remembered

### Moving things

**Payload**:
Anything a user moves: text, a link, one or more files, or clipboard content.
A Payload is typed, and its type decides how the receiving Device handles it.
_Avoid_: Content, Data, Body, Blob, Item

**Transfer**:
One user-initiated act of sending a Payload to one or more Devices.
_Avoid_: Send, Upload, Share, Job, Task, Push

**Session**:
The negotiated exchange that carries a Transfer, from offer to completion.
_Avoid_: Connection, Channel, Stream, Socket

### Clipboard

**ClipboardEntry**:
A Payload captured from a Device's system clipboard, tagged with the Device it
came from.
_Avoid_: Clip, Copy, ClipboardItem, Paste

**Mirror**:
A clipboard mode in which an incoming ClipboardEntry replaces the receiving
Device's system clipboard with no user action. Available only within an Owner
Group. Mirroring is **directional**: a Device may be able to *apply* a Mirror
without being able to *originate* one, because platforms restrict reading the
clipboard far more tightly than writing it.
_Avoid_: Sync, AutoPaste, Push, Auto

**Clipboard Capability**:
What a Device can actually do with the clipboard given its platform: whether
it can detect a local copy (`canOriginate`) and whether it can apply an
incoming ClipboardEntry (`canApply`). Declared by each Device and shown in the
UI, so no Device is presented as capable of something its platform forbids.
_Avoid_: Permission, Feature Flag, Support Level

**Stage**:
A clipboard mode in which an incoming ClipboardEntry waits until the user
explicitly accepts it into the system clipboard.
_Avoid_: Manual, Hold, Queue, Pending
