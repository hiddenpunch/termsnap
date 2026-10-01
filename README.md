# termsnap

Ghostty의 창·탭·분할을 그 안에서 돌던 세션과 함께 저장했다가, 재부팅이나 충돌 뒤에 그대로 되살린다. Claude Code와 Codex는 각자 대화를 이어간다.

```text
재부팅 → termsnap restore → 창 2개 · 탭 17개 · 분할 32개가 원래 폴더에서 열리고
                            Claude Code 20개 · Codex 5개가 대화를 이어감
```

## 필요한 것

- macOS, [Ghostty](https://ghostty.org) 1.3 이상 (AppleScript 지원)
- Homebrew (설치되어 있으면 macOS 기본 파이썬도 함께 있다)

## 설치

```bash
brew tap hiddenpunch/tap
brew install termsnap
brew services start termsnap     # 5분마다 자동 저장, 로그인 시 자동 시작
```

처음 저장할 때 macOS가 Ghostty 제어 권한을 묻는다. 허용해야 창 구조를 읽을 수 있다.

## 쓰는 법

```bash
termsnap snapshot                 # 지금 상태 저장
termsnap show                     # 저장본에 무엇이 있는지 보기
termsnap restore                  # 되살리기
termsnap restore --mode missing   # 이미 떠 있는 세션은 건너뛰고 없는 것만
termsnap restore --dry-run        # 열지 않고 실행될 내용만 보기
```

복원하면 분할마다 이렇게 열린다.

| 분할에서 돌던 것 | 복원 |
|---|---|
| Claude Code | `claude --resume <세션 ID>` 를 원래 옵션과 함께 실행 |
| Codex | `codex resume <세션 ID>` 실행 |
| 그 밖의 명령 (`ngrok`, `k9s` 등) | 명령을 입력만 해 둔다. `--run-all` 이면 실행 |
| 빈 셸 | 원래 폴더에서 연다 |

## 복원 지점

저장할 때마다 직전 상태와 비교해서, 세션이 절반 이상 한꺼번에 사라졌으면 사라지기 직전 상태를 복원 지점으로 따로 남긴다. `termsnap restore` 는 복원 지점이 있으면 그것을 되살린다. 사라진 경로도 기록한다.

| 경로 | 판정 |
|---|---|
| 재부팅 | 부팅 시각이 직전 저장보다 뒤 |
| 로그아웃 후 로그인 | 로그인 시각이 직전 저장보다 뒤 |
| Ghostty 충돌 | 직전 저장 뒤에 Ghostty 충돌 보고서가 생김 |
| Ghostty 종료, 창 닫음 | 그 외 |

## 메뉴 막대 앱

`app/` 의 메뉴 막대 앱은 같은 스크립트를 앱 안에 넣어 쓴다. 상단바에서 저장본을 골라 복원하고, 재부팅·로그아웃·충돌로 세션이 사라지면 빨간 점으로 알려 준다. 터미널이 이미 열려 있으면 "없는 것만 추가로 열기", "중복 상관없이 전부 추가로 열기", "기존 터미널을 전부 종료하고 열기" 중에서 고른다.

```bash
app/build.sh       # ~/Applications/Termsnap.app 에 빌드·설치 (Xcode 명령줄 도구만 있으면 된다)
app/make_dmg.sh    # app/dist/Termsnap.dmg
```

서명하지 않은 앱이라 다른 Mac에서 처음 열 때 막히면 우클릭 → 열기, 또는:

```bash
xattr -dr com.apple.quarantine /Applications/Termsnap.app
```

## 저장 위치

| 파일 | 내용 |
|---|---|
| `~/.termsnap/latest.json` | 가장 최근 상태 |
| `~/.termsnap/snap-*.json` | 상태가 바뀔 때마다 남는 기록, 최근 200개 |
| `~/.termsnap/restore-point.json` | 세션이 한꺼번에 사라지기 직전 상태 |
| `~/.termsnap/before-replace.json` | "전부 종료하고 열기" 직전 상태 |

## 동작 방식과 한계

- Ghostty AppleScript로 창·탭·분할 구조와 분할별 제목·폴더를 읽고, 복원할 때 같은 구조를 새로 만든다.
- 분할마다 돌던 프로세스는 `ps`·`lsof` 로 찾는다. Claude Code 세션 ID는 `~/.claude/sessions/`, Codex 세션 ID는 `~/.codex/sessions/` 의 기록 파일에서 읽는다.
- 분할과 프로세스는 터미널 제목과 폴더로 짝짓는다. Claude Code는 대화 제목이 터미널 제목에 나와서 같은 폴더에 여러 개 있어도 구분된다. 같은 폴더의 Codex 두 개는 서로 바뀔 수 있다.
- 분할의 방향과 비율은 Ghostty AppleScript가 알려 주지 않아서 모두 오른쪽으로 나뉜다.
- Claude Code·Codex의 내부 파일과 Ghostty AppleScript 사전은 공식 API가 아니라서 업데이트로 바뀌면 깨질 수 있다.

## 라이선스

MIT
