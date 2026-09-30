# Space Labels

<img src="Assets/AppIcon.png" alt="겹친 창과 이름표 모양의 Space Labels 아이콘" width="96">

Mission Control에 나타나는 **일반 데스크톱, 전체 화면 앱, Split View 공간, 개별 앱 창**에 별도 이름을 붙이는 메뉴 막대 앱입니다. Mission Control 항목 우클릭으로 이름 입력 창을 여는 동작을 개발 중입니다. macOS 자체의 공간 이름이나 앱의 창 제목은 바꾸지 않으며, 앱이 표시용 이름을 저장하고 화면에 겹쳐 보여 줍니다.

현재 빌드는 macOS 26.6.2의 Apple Silicon에서 제작했습니다. 실제 Mission Control에서 공간과 창은 인식하지만 우클릭 편집창은 열리지 않는 것을 확인했습니다. 입력 감시 권한을 확인 중이며, 여러 디스플레이 동작은 미검증입니다. [검사 결과](docs/testing.md)를 확인하십시오.

이 저장소는 개발 중인 소스를 공개합니다. 현재 우클릭 기능이 작동하지 않으므로 설치용 실행 파일이나 정식 릴리스를 제공하지 않습니다. 직접 빌드하더라도 이 제한이 적용됩니다.

## 시작

1. `Space Labels.app`을 여십시오. 앱이 이미 실행 중일 때 다시 열면 설정 창이 나타납니다.
2. 설정 창을 닫았으면 메뉴 막대의 겹친 창·이름표 아이콘에서 **이름 및 설정…**을 다시 여십시오.
3. **권한 설정 열기**가 보이면 macOS 접근성 권한을 허용하십시오. 이미 허용으로 표시되는데도 안내가 남아 있다면 [권한 복구 절차](docs/user-guide.md)를 따르십시오.
4. Mission Control을 열고 상단 공간이나 아래 앱 창을 우클릭해 이름을 입력하십시오.

앱 창에서도 모든 공간의 이름을 편집할 수 있습니다. 자세한 사용법은 [사용 안내](docs/user-guide.md)에 있습니다.

## 소스와 검사

Swift Package Manager 프로젝트입니다. `SpaceLabelsCore`는 이름 규칙과 저장을 담당하고, `SpaceLabels`는 macOS 조회와 화면 표시를 담당합니다. macOS 14 이상과 Xcode 명령줄 도구가 필요합니다. 프로젝트 폴더에서 아래 명령을 실행하십시오.

```sh
swift test --disable-sandbox --scratch-path .build
python3 scripts/check-docs.py
./scripts/build-app.sh "$PWD/dist"
```

빌드한 앱은 `dist/Space Labels.app`에 만들어집니다. 앱 아이콘은 제공된 원본 PNG에서 빌드 시 생성하므로 이미지 생성 도구가 필요하지 않습니다. 빌드와 검사의 자세한 내용은 [검사 문서](docs/testing.md), 구조와 식별 규칙은 [설계 문서](docs/architecture.md)에 있습니다. [호환성](docs/compatibility.md)과 [배포](docs/releasing.md)도 확인하십시오.

소스와 아이콘 원본은 [MIT 라이선스](LICENSE)를 따릅니다. 오류 제보나 변경 제안에는 사용한 macOS 버전, 재현 절차, 실제 결과를 적어 주십시오. 화면 내용이나 저장된 이름처럼 개인 정보가 담긴 자료는 공개 이슈에 올리기 전에 가리십시오.
