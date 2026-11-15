Family Hub 설치 안내 (약 20분)

★ v1.1 업데이트(가족 여행)만 하는 경우
   1. Supabase SQL Editor 에 familyhub_schema.sql 전체를 다시 붙여넣고 Run
      (여러 번 실행해도 기존 데이터는 그대로 — 새 여행 테이블·함수만 추가됩니다)
   2. index.html 의 SB_URL·SB_KEY 를 지금 쓰는 값으로 바꾼 뒤 저장소에 덮어쓰기
================================================================
준비물: Supabase 계정, GitHub 계정 (mujjinhwan-prog)

────────────────────────────────────────
1) Supabase 새 프로젝트 만들기 (가족 전용)
────────────────────────────────────────
 - supabase.com → New project → 이름: familyhub, 지역: Northeast Asia (Seoul)
 - 만들어지면 Project Settings → API 에서 두 값을 복사해 둡니다.
     · Project URL   (https://xxxx.supabase.co)
     · anon public 키 (또는 Publishable key)

────────────────────────────────────────
2) SQL 한 번 실행
────────────────────────────────────────
 - 왼쪽 SQL Editor → New query → setup/familyhub_schema.sql 전체 붙여넣기 → Run
 - "Success" 가 나오면 끝. 가족 4명·기본 보상 4개가 자동으로 들어갑니다.
   (진환 = admin, 처음 비밀번호는 각자 생일 6자리: 800826 / 830613 / 160525 / 210113)

────────────────────────────────────────
3) 파일에 Supabase 값 넣기 (2곳)
────────────────────────────────────────
 - index.html       맨 아래 설정의 SB_URL, SB_KEY
 - admin/index.html 맨 아래 설정의 SB_URL, SB_KEY   (같은 값)

────────────────────────────────────────
4) GitHub Pages 올리기
────────────────────────────────────────
 - GitHub 새 저장소: familyhub (Public)
 - 압축 푼 폴더 안의 것들을 폴더째 끌어다 놓기:
     index.html, sw.js, manifest.webmanifest, icons/, admin/, games/
   ※ setup 폴더는 올리지 마세요 (설치용 파일)
 - Settings → Pages → Branch: main / (root) → Save
 - 주소: https://mujjinhwan-prog.github.io/familyhub/
   (원하면 family.ourclinic.kr 처럼 서브도메인 연결 가능 — 다른 앱과 같은 방법)

────────────────────────────────────────
5) 휴대폰 알림 서버 연결 (5분, 선택이지만 추천)
────────────────────────────────────────
 이걸 해야 비밀 메시지·새 글·생일·D-day 알림이 잠금화면에 뜹니다.
 (안 하면 앱을 열었을 때 홈 화면에서만 알림이 보입니다)

 a. Supabase → Edge Functions → Deploy a new function → Via Editor
    - 함수 이름: fh-push
    - setup/supabase-function/index.ts 내용 통째로 붙여넣고 Deploy
    - 함수 설정에서 "Verify JWT"(Enforce JWT verification) 를 OFF

 b. Edge Functions → Secrets 에 3개 추가 (familyhub_keys.txt 값 복사)
      VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / PUSH_SECRET

 c. SQL Editor 에서 아래 2줄 실행 (<프로젝트ID> 만 바꿔서)
    insert into public.app_secrets values ('push_url', 'https://<프로젝트ID>.supabase.co/functions/v1/fh-push') on conflict (key) do update set value = excluded.value;
    insert into public.app_secrets values ('push_secret', '<familyhub_keys.txt 의 PUSH_SECRET 값>') on conflict (key) do update set value = excluded.value;

 d. 확인: 앱 → 내 설정 → 휴대폰 알림 받기 ON → [테스트 알림 보내기]
    admin → 현황·설정 에서 "알림 서버 ✅ 연결됨", 아침 8시/저녁 9시 예약이 보이면 완료.

────────────────────────────────────────
6) 가족 폰에 설치
────────────────────────────────────────
 - 안드로이드: 크롬으로 주소 열기 → ⋮ → 앱 설치(홈 화면에 추가)
 - 아이폰: Safari로 열기 → 공유 버튼 → 홈 화면에 추가
   (아이폰 알림은 홈 화면에 추가한 앱에서만 켤 수 있어요)
 - 처음 로그인하면 비밀번호를 바꾸라는 화면이 나옵니다.
   효양이처럼 어린 아이는 부모님이 같이 정해 주세요.

────────────────────────────────────────
참고
────────────────────────────────────────
 - 비밀 메시지: 앱·admin 어디에서도 보낸 사람/받는 사람 외에는 볼 수 없습니다.
   (Supabase 대시보드 Table Editor 에서는 프로젝트 주인이 기술적으로 볼 수 있습니다)
 - 위치 공유: 웹앱 특성상 앱을 열어둔 동안에만 위치를 보냅니다.
 - Digital Hub: 각자 폰에만 저장됩니다. 폰 바꾸기 전에 [백업 파일 받기].
 - 사진: 자동으로 줄여서 저장. 무료 500MB 로 약 2,000장.
 - 가족 추가·삭제, 비밀번호 초기화, 보상 승인, 포인트 규칙: admin 사이트 (앱 → 더보기 → admin)
