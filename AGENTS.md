# 작업 안내

이 프로젝트의 사람용 원본 문서는 아래 파일입니다. 기능을 바꾸면 해당 문서를 같은 작업에서 갱신하십시오.

| 내용 | 원본 |
| --- | --- |
| 시작과 사용 | [README.md](README.md), [사용 안내](docs/user-guide.md) |
| 공간·창 식별과 저장 | [설계](docs/architecture.md) |
| 확인한 환경과 제한 | [호환성](docs/compatibility.md) |
| 검사 절차와 결과 | [검사](docs/testing.md) |
| 서명과 배포 | [배포](docs/releasing.md) |
| 아이콘 원본과 생성 절차 | [설계](docs/architecture.md), [배포](docs/releasing.md) |
| 공개 범위와 라이선스 | [README.md](README.md), [LICENSE](LICENSE) |

Swift 검사는 `swift test --disable-sandbox --scratch-path .build`로 실행하십시오. 앱은 `./scripts/build-app.sh <출력 폴더>`로 만드십시오. 아이콘만 확인할 때는 `./scripts/build-icon.sh .build/AppIcon.icns`를 실행하십시오. 문서 링크와 목록은 `python3 scripts/check-docs.py`로 확인하십시오. 실행한 검사만 문서에 완료로 기록하십시오.

브랜치를 만들면 `<type>/<작업 내용>` 형식을 사용하십시오. 브랜치 이름에 AI 도구 이름을 넣지 마십시오.
