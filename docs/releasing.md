# 배포 준비

MIT 라이선스의 소스와 함께 Apple Silicon용 시험판 DMG를 GitHub의 사전 출시 버전으로 제공합니다. [바로 다운로드](https://github.com/taehun2123/space-labels/releases/download/v0.1.0-preview.1/Space-Labels-0.1.0-preview.1-macos-arm64.dmg)할 수 있습니다. 우클릭 편집창은 실제 화면에서 열리지 않으므로 정식 릴리스로 표시하지 않습니다. 저장소의 자동 검사는 빌드와 단위 검사만 확인하며 Mission Control 조작의 성공을 뜻하지 않습니다.

시험판 앱은 임시 서명입니다. 이 Mac에서 Developer ID 코드 서명 인증서를 찾지 못해 Apple 공증을 진행하지 않았습니다. 설치할 때 macOS가 실행을 막으면 [시험판 설치 안내](user-guide.md)를 확인하십시오.

임시 서명으로 다시 빌드하면 macOS가 이전 빌드에 허용한 접근성 권한을 새 실행 파일에 적용하지 않을 수 있습니다. 새 빌드를 전달한 뒤에는 [권한 복구 절차](user-guide.md)에 따라 실제 앱 파일을 다시 등록하고, 앱의 권한 안내가 사라졌는지 확인하십시오.

시험판 DMG를 다시 만들려면 Apple Silicon Mac의 프로젝트 폴더에서 `./scripts/package-preview.sh 0.1.0-preview.1 <출력 폴더>`를 실행하십시오. 이 스크립트는 앱을 빌드하고 Applications 바로 가기가 있는 DMG를 만듭니다. 업로드 전에는 DMG를 마운트해 앱과 바로 가기를 확인하고, 앱 서명과 SHA-256 값을 검사하십시오.

정식 배포 전에는 다음을 완료하십시오.

1. 상단 공간과 개별 앱 창의 우클릭 입력창, 이름 표시를 실기기에서 확인하십시오.
2. Apple Developer 계정의 Developer ID Application 인증서를 준비하십시오.
3. 안정된 bundle ID와 버전을 정하고 앱을 Developer ID로 서명하십시오.
4. ZIP 또는 DMG를 만들고 Apple 공증을 요청한 뒤 티켓을 첨부하십시오.
5. 새로 설치한 앱에 접근성 권한을 허용하고 [실기기 확인 절차](testing.md)를 다시 수행하십시오.
6. 지원 OS와 디스플레이 구성을 [호환성 문서](compatibility.md)에 확인된 결과만 기록하십시오.

앱 아이콘은 `Assets/AppIcon.png`에서 `scripts/build-icon.sh`로 생성합니다. `scripts/build-app.sh`가 이를 자동으로 호출해 앱 리소스에 복사한 뒤 서명합니다. 로컬에서 아이콘 묶음만 다시 만들려면 프로젝트 폴더에서 `./scripts/build-icon.sh .build/AppIcon.icns`를 실행하십시오.

SkyLight와 Mission Control의 비공개 동작에 의존하므로 Mac App Store 배포를 전제로 하지 않습니다. 다른 Mac에 전달하기 전에는 해당 OS에서 실제 이름 표시와 우클릭 동작을 확인해야 합니다.
