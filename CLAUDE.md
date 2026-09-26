# 굿즈샵 (goods-shop)

굿즈를 파는 작은 쇼핑몰. 회원가입/로그인(또는 비회원) → 장바구니 → 토스페이먼츠(테스트 모드) 결제 → 결제 내역 확인, 관리자는 전체 결제 내역 확인.
세부 구조(테이블, 보안 규칙, 결제 흐름, 파일별 역할)는 [ARCH.md](ARCH.md) 참고.

## 사용자
- 코딩 입문자. 설명과 질문은 **쉬운 한국어**로, 전문 용어는 풀어서.

## 기술 구성
- **화면:** 순수 HTML/CSS/JS (빌드 도구·프레임워크 없음). GitHub Pages로 배포.
  - 저장소: `jhhan-git/goods-shop` (public, `main` 브랜치 루트가 그대로 사이트)
  - 주소: https://jhhan-git.github.io/goods-shop/
- **백엔드:** Supabase (프로젝트 `goods-shop`, ref `ooirdvyqpdtvxsmatwda`, 서울 리전, Free)
  - Auth(이메일+비밀번호, 비회원용 익명 로그인), Postgres + RLS, Edge Function `confirm-payment`
  - supabase-js v2는 CDN(`cdn.jsdelivr.net/npm/@supabase/supabase-js@2`)으로 로드
- **결제:** 토스페이먼츠 결제위젯 v2 (`js.tosspayments.com/v2/standard`), 공개 문서용 테스트 키 사용

## 페이지
| 파일 | 역할 |
|---|---|
| `index.html` | 상품 목록, 장바구니 담기 |
| `cart.html` | 장바구니 + 토스 결제위젯 (회원 로그인 또는 비회원 구매) |
| `success.html` / `fail.html` | 결제 결과 (success에서 서버 승인 호출) |
| `login.html` | 회원가입/로그인 |
| `orders.html` | 내 결제 내역 (비회원은 이 브라우저의 주문) |
| `guest-order.html` | 비회원 주문 조회 (주문번호 + 이메일) |
| `admin.html` | 관리자 전용: 전체 결제 내역 |

## 꼭 지킬 규칙
- **가격은 서버에서 계산한다.** 주문은 `create_order` RPC로만 만들고, 금액은 DB `products.price` 기준. 브라우저가 보낸 금액을 믿지 않는다.
- **주문 상태 변경은 Edge Function(`confirm-payment`)만 한다.** 브라우저(anon/authenticated)는 모든 테이블에 대해 읽기만 가능(insert/update/delete 권한 회수됨).
- **시크릿 키는 코드에 넣지 않는다.** 토스 시크릿 키는 Supabase 비밀값 `TOSS_SECRET_KEY`에만 있다. `js/config.js`에는 공개 가능한 값(Supabase URL, publishable key, 토스 클라이언트 키)만.
- **저장소가 공개**이므로 비밀번호·토큰을 파일에 쓰지 않는다.
- 회원가입 **이메일 인증은 꺼져 있다** (Auth 설정 `mailer_autoconfirm: true`). 가입 즉시 로그인됨.
- **비회원 구매 = Supabase 익명 로그인.** 비회원은 `signInAnonymously()`로 임시 계정(`user.is_anonymous`)을 받아 회원과 같은 RLS·결제 흐름을 탄다. 주문 시 연락 이메일을 받아 `orders.user_email`에 저장하고 `is_guest=true`. 화면에서 회원/비회원 구분은 `isGuest(user)`로 한다(익명 사용자도 `getUser()`는 값이 있음).
- 관리자 판별은 `admins` 테이블 + `is_admin()` 함수. 관리자 계정: `admin@admin.com` (비밀번호는 저장소에 기록하지 않음).
- DB 스키마 변경은 `supabase/migrations/`에 SQL 파일을 추가하고 Supabase MCP `apply_migration`으로 적용.
- 새 파일에서도 사용자 입력/DB 값을 HTML에 넣을 때는 `esc()`로 이스케이프.
- **화면·디자인 작업은 `goods_shop_design_funcoding` 스킬을 따른다.** 특히 금지 규칙: 이모지·아이콘 금지(글자로만), 정해진 색 변수만, 같은 뜻은 같은 단어.
- 상품 사진은 `images/products/`에 800×600 JPG로 넣고 `products.image_url`에 상대 경로를 저장한다. 외부 사진을 쓰면 `images/products/CREDITS.md`에 출처를 적는다.

## 배포
- 화면: `main`에 push하면 GitHub Pages가 자동 배포(1~2분).
- Edge Function: `supabase/functions/confirm-payment/index.ts` 수정 후 Supabase MCP `deploy_edge_function`(verify_jwt: true)으로 배포.
- GitHub 토큰은 Windows 사용자 환경변수 `GH_TOKEN`. 현재 셸에 없으면 PowerShell에서
  `$env:GH_TOKEN=[Environment]::GetEnvironmentVariable("GH_TOKEN","User")`.

## 테스트 결제
토스 테스트 모드라 실제 돈이 나가지 않는다. 결제창에서 아무 카드나 선택해 진행하면 된다.
