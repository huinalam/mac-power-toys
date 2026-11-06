# Mac Power Toys

[English](../README.md) | 한국어

**초기 개발 버전입니다.** 단축키 전환 시 메뉴 막대가 간헐적으로 사라지는 문제가 조사 중입니다. [알려진 문제](KNOWN_ISSUES.md)를 확인하세요. Microsoft 또는 Apple의 공식 제품이 아닙니다.

SwiftUI + AppKit으로 만든 macOS 메뉴 막대 유틸리티입니다. 첫 기능은 앱별 전역 단축키를 통한 실행 및 전환입니다.

## 빌드 및 실행

아래 명령은 저장소 루트에서 실행합니다. 최소 배포 대상은 macOS 14이며 실제 수동 확인 환경은 macOS 27.0.1 / Apple Silicon입니다. 모든 지원 버전의 검증이 완료된 것은 아닙니다.

- macOS 14 이상
- Swift 6.2 이상을 포함한 전체 Xcode (의존성의 SwiftUI 매크로 때문에 Command Line Tools만으로는 빌드할 수 없습니다)
- 최초 빌드 시 Swift Package 다운로드를 위한 네트워크 연결

```sh
./scripts/build-app.sh
open "dist/Mac Power Toys.app"
```

배포용 폴더에 Apple Silicon 및 Intel용 Universal 앱을 생성하고 로컬 실행용 ad-hoc 서명을 적용합니다. 로그인 시 실행을 사용하려면 앱을 `/Applications`로 옮긴 후 그 위치에서 실행하세요. 외부 배포용 Developer ID 서명 및 공증은 포함되어 있지 않습니다.

빌드 스크립트는 선택된 개발 도구가 Command Line Tools일 경우 `/Applications/Xcode*.app`을 찾아 해당 빌드에만 사용합니다. 테스트 명령의 Xcode 경로는 설치 환경에 맞게 변경하세요.

Xcode에서는 `Package.swift`를 열어 소스를 편집할 수 있습니다. 메뉴 막대/로그인 항목을 확인할 때는 위 스크립트로 만든 앱 번들을 실행하세요.

## 사용 방법

1. 첫 실행 시 표시되는 설정에서 **앱 추가**를 선택합니다. 여러 앱을 동시에 선택할 수 있습니다.
2. 앱 옆의 단축키 입력란을 클릭하고 원하는 조합을 누릅니다.
3. 단축키를 누르는 순간 앱을 실행하거나 전환합니다. 조합키를 놓을 필요가 없습니다.
4. 설정 창을 닫아도 메뉴 막대에 상주합니다. 메뉴 막대의 ⌘ 아이콘으로 설정, 전체 일시 정지, 종료를 선택합니다.

앱별 토글로 단축키를 비활성화할 수 있습니다. 재생 버튼은 수동 실행 테스트용이며 일시 정지 상태에서도 동작합니다. 휴지통 버튼은 등록만 제거하고 실제 앱은 삭제하지 않습니다. 이미 앞에 있는 앱은 그대로 유지합니다.

설정은 앱의 UserDefaults에 저장됩니다. 앱 내부 단축키 중복은 비활성 항목을 포함해 차단합니다. KeyboardShortcuts가 시스템/메뉴 충돌 안내와 단축키 저장을 담당합니다. 다른 모든 앱이 사용하는 단축키를 탐지할 수는 없습니다.

## 구조

- `AppStore`: 앱 등록, 전역 단축키, 실행, 일시 정지, 로그인 항목
- `AppEntry` / `SettingsRepository`: 앱 식별 및 설정 저장
- `SettingsView`: SwiftUI 설정 화면
- `AppDelegate`: AppKit 메뉴 막대와 설정 창 수명 관리

앱의 저장된 경로를 먼저 확인하고, 위치가 변경되면 Bundle ID로 다시 찾습니다. 접근성/입력 모니터링 권한을 요청하지 않습니다. 특정 창 선택, 최소화 창 복원, 강제 Space 이동은 구현 범위에 포함하지 않습니다. 활성화 이후 창 표시와 Space 전환은 macOS와 대상 앱 설정을 따릅니다. 실행 중인 앱도 Launch Services로 열기 때문에 창이 없는 앱은 대상 앱의 reopen 처리에 따라 새 창이 열릴 수 있습니다.

전역 단축키는 key-down에 즉시 처리하며 조합키 해제나 추가 지연을 기다리지 않습니다. 대기 중에는 마지막 요청만 유지하며, 이미 제출한 열기 요청의 완료 콜백을 받은 뒤 다음 요청을 처리합니다. 이미 macOS에 전달한 요청은 취소할 수 없고 완료 콜백도 화면 전환 완료를 보장하지 않습니다. 실행 중인 앱을 별도로 unhide/activate하지 않고, 실행과 전환 모두 `NSWorkspace.openApplication`의 활성화 경로를 사용합니다. 시스템 메뉴 막대 자동 숨김 설정은 변경하지 않습니다.

## 검증

```sh
./scripts/test.sh
./scripts/build-app.sh
```

수동 확인 항목:

- 앱 추가 → 단축키 지정 → 다른 앱에서 전환
- 종료된 앱 실행, 숨긴 앱 활성화, 현재 앱 재입력
- 중복 단축키 거부, 단축키 변경 및 삭제
- 개별 비활성화와 전체 일시 정지 후 키가 원래 앱으로 전달되는지
- 설정 창을 닫은 후 동작, 종료 후 재실행 시 설정 유지
- 앱 이동/삭제 후 경로 재탐색 및 오류 표시
- 한/영 입력 전환, 다른 Space, 전체 화면, 최소화 상태
- `/Applications` 설치 후 로그인 시 실행 및 시스템 설정 승인 상태

## 참고 및 라이선스

이 프로젝트는 [MIT 라이선스](../LICENSE)를 적용합니다.

사용 경험은 [Thor](https://github.com/gbammc/Thor)에서 영감을 받았습니다. Thor 소스 코드는 복사하지 않았습니다.
단축키 구현은 MIT 라이선스의 [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 3.1.0을 사용합니다. 고지는 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)에 포함합니다.

## 앱 전환 진단 로그

메뉴 막대 메뉴의 **진단 로그 폴더 열기…**에서 다음 폴더를 엽니다.

```text
~/Library/Logs/MacPowerToys/
  activation.jsonl
```

로그는 최근 **24시간**, 총 **256 KiB** 이내로 유지합니다. 시간 또는 용량 제한을 넘으면 오래된 기록부터 삭제합니다. 앱 시작, 기록 추가, 실행 중 15분마다 정리하므로 유휴 상태에서는 만료 후 최대 약 15분까지 남을 수 있습니다. 앱이 종료되어 있으면 다음 실행 때 정리합니다. 기존 rotation 파일도 이 정책으로 통합·정리합니다. 디스크 쓰기는 별도 직렬 큐에서 처리합니다. 앱 Bundle ID와 PID를 포함하지만 창 제목, 문서 내용, 입력 문자, 전체 파일 경로는 수집하지 않습니다. 진단 기록은 이 로컬 파일에만 저장하며 시스템 Console에 중복 기록하지 않습니다. 파일 쓰기 실패만 시스템 로그에 남깁니다. 이전 버전이 이미 남긴 시스템 로그는 macOS 보존 정책을 따릅니다.

각 전환에는 `request` ID가 붙습니다. `switch.request` → 3초 후 `switch.result`와 `workspace.activated`, `workspace.spaceChanged`를 비교하세요. 정상 열기 제출·완료 로그와 중간 반복 샘플은 생략하며, 오류가 발생한 완료 콜백은 기록합니다. 빠르게 다른 앱을 요청하면 이전 요청의 후속 샘플은 취소하고 최신 요청을 추적합니다. Workspace 알림은 요청 후 약 3.5초 동안만 기록하며, 그 사이 사용자가 직접 전환한 이벤트도 포함될 수 있습니다. 알림의 요청 ID는 관찰 구간을 나타내며 인과관계를 보장하지 않습니다.

- `source`: 수동 실행 / 단축키 key-down 실행 구분
- `frontmost`, `targetActive`, `targetHidden`: 실제 활성 앱과 대상 앱 상태
- `systemPresentationRaw`, `hideMenuBar`, `autoHideMenuBar`, `fullScreen`: 시스템 presentation 옵션
- `menuBarVisible`: AppKit이 보고하는 메뉴 막대 표시 상태
- `statusItemVisible`: 우리 메뉴 막대 아이콘의 표시 상태(화면에서 가려지는지까지 보장하지 않음)
- `modifierFlags`: 전환 요청 때 남아 있는 modifier 키 상태(입력 문자가 아님)
- `errorDomain`, `errorCode`: 열기 요청 오류. 성공 콜백도 실제 활성화 완료를 보장하지 않습니다.

증상 재현 후 메뉴 막대가 돌아오면 **메뉴 막대 문제 시점 기록**을 선택하고 대략적인 발생 시간을 함께 남겨주세요. 이 표식의 시간은 클릭한 시점이며 실제 증상 발생 시점은 아닙니다. `targetActive=true`인데 `hideMenuBar=true`라면 표시 정책 전환을, 대상 앱이 전면에 오지 않았다면 활성화 실패를 조사할 단서가 됩니다. `menuBarVisible=true`인데 화면에서 보이지 않는 경우 렌더링/디스플레이 문제 가능성도 있어 로그만으로 원인을 확정할 수 없습니다.
