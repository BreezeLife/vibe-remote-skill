# Third-party notices

VibeRemote's ATVV protocol and IMA/DVI ADPCM decoder adapt MIT-licensed bridge
source from [VincentKingHsu/MiRemoteVoice](https://github.com/VincentKingHsu/MiRemoteVoice),
revision `2c374d9d65ed6c8b1af6a4f9aa1b6c0f8a039aaf`:

- `mi-remote-bridge/Sources/MiRemoteBridge/ATVV/ATVVProtocol.swift`
- `mi-remote-bridge/Sources/MiRemoteBridge/ATVV/ADPCMDecoder.swift`
- `mi-remote-bridge/Sources/MiRemoteBridge/BLEBridge.swift` (CoreBluetooth connection flow)
- `mi-remote-bridge/SelfTests/main.swift` (stream synchronization regression scenarios)

MiRemoteVoice identifies [fanxeon/mi-ao](https://github.com/fanxeon/mi-ao) as the
MIT-licensed source of its bridge implementation. Its protocol/decoder also reference
[b0o/ATVVoice](https://github.com/b0o/ATVVoice), which is MIT licensed. VibeRemote's
ADPCM step table follows ATVVoice's standard IMA/DVI values.

The applicable copyright notices are retained below. The same MIT license text applies
to each of these components:

```text
Copyright (c) 2026 Sima Qingfeng
Copyright (c) 2026 FanXeon@Poemcoder with Codex
Copyright (c) 2026 Maddison Cohodas

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The protocol constants and packet layouts were checked against the
[Google Voice over BLE specification 1.0](https://wangefan.github.io/linux_kernel_driver/resources/Google_Voice_over_BLE_spec_v1.0.pdf)
(Google, Inc., 2020). The document is referenced, not distributed with this application.

This application does not include MiRemoteVoice's HAL driver, BlackHole binaries,
driver modification scripts, or their GPL-licensed code. Audio decoding runs inside
VibeRemote and produces PCM for its own speech recognition pipeline.
