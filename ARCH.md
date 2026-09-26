# 굿즈샵 구조 (ARCH)

프로젝트 개요와 규칙은 [CLAUDE.md](CLAUDE.md) 참고.

## 폴더 구조
```
/
├── index.html            상품 목록
├── cart.html             장바구니 + 결제위젯
├── success.html          결제 성공 → 서버 승인 요청
├── fail.html             결제 실패 안내
├── login.html            회원가입 / 로그인
├── orders.html           내 결제 내역 (비회원: 이 브라우저의 주문)
├── guest-order.html      비회원 주문 조회
├── admin.html            관리자: 전체 결제 내역
├── css/style.css         공통 스타일 (규칙: .claude/skills/goods_shop_design_funcoding)
├── images/products/      상품 사진 (Unsplash License, 출처는 CREDITS.md)
├── js/
│   ├── config.js         공개 설정값 (Supabase URL/키, 토스 클라이언트 키)
│   ├── cart.js           장바구니 (localStorage)
│   └── common.js         Supabase 클라이언트, 로그인 확인, 상단 메뉴, 도우미
└── supabase/
    ├── migrations/001_init.sql          테이블·RLS·함수·예시 상품
    ├── migrations/002_guest_checkout.sql 비회원 구매 (is_guest, create_order 교체, find_guest_order)
    ├── migrations/003_product_photos.sql 상품 사진 경로 입력, emoji 칸 삭제
    └── functions/confirm-payment/index.ts  결제 승인 Edge Function
```

모든 페이지는 `<head>`에서 같은 순서로 스크립트를 불러온다:
`supabase-js(CDN) → js/config.js → js/cart.js → js/common.js`, 그리고 페이지 전용 코드는 `<body>` 끝의 인라인 `<script>`.
`cart.html`만 토스 SDK(`https://js.tosspayments.com/v2/standard`)를 추가로 로드한다.

## JS 모듈
### `js/common.js`
| 이름 | 설명 |
|---|---|
| `sb` | Supabase 클라이언트 |
| `getUser()` | 현재 로그인 사용자 또는 `null` (비회원 임시 계정 포함) |
| `isGuest(user)` | 비회원(익명 로그인) 사용자인지 |
| `isAdmin()` | `rpc('is_admin')` 결과 |
| `requireLogin()` | 비로그인 시 `login.html?next=<현재 페이지>`로 이동 |
| `renderNav()` | `#nav`에 상단 메뉴 렌더 (DOMContentLoaded 시 자동) |
| `won(n)`, `formatDate(iso)`, `esc(s)`, `statusBadge(status)`, `toast(msg)` | 표시용 도우미 |

### `js/cart.js`
localStorage 키 `goods-cart`에 `[{ product_id, quantity }]` 저장.
`getCart`, `saveCart`, `addToCart`, `setCartQuantity`(1~99), `removeFromCart`, `clearCart`, `cartCount`, `updateCartBadge`.

## 데이터베이스
| 테이블 | 주요 컬럼 |
|---|---|
| `products` | `id`, `name`, `description`, `price`, `image_url`(사이트 기준 상대 경로, 예: `images/products/mug.jpg`. 없으면 화면에 상품 이름 글자를 표시) |
| `orders` | `id`(uuid, 토스 orderId로 사용), `user_id`, `user_email`(비회원은 입력한 연락 이메일), `is_guest`, `order_name`, `total_amount`, `status`(`pending`/`paid`/`failed`), `payment_key`, `payment_method`, `approved_at`, `created_at` |
| `order_items` | `order_id`, `product_id`, `product_name`, `unit_price`(주문 시점 가격), `quantity`(1~99) |
| `admins` | `user_id` — 관리자 목록 |

### 권한과 RLS
- `anon`, `authenticated` 역할은 네 테이블 모두 **insert/update/delete 권한이 회수**되어 있다. 쓰기는 `create_order`(security definer)와 Edge Function(service role)만 한다.

| 테이블 | SELECT 정책 |
|---|---|
| `products` | 누구나 |
| `orders` | `user_id = auth.uid()` 또는 `is_admin()` |
| `order_items` | 해당 주문을 볼 수 있는 사람 |
| `admins` | 자기 행만 |

### 함수
- `is_admin() → boolean` — `admins`에 현재 사용자가 있는지. authenticated만 실행 가능.
- `create_order(items jsonb, guest_email text default null) → (order_id, amount, order_name)` — 비회원(JWT `is_anonymous`)이면 `guest_email`이 필수이고 소문자로 저장, `is_guest=true`. 장바구니 `[{product_id, quantity}]`를 받아 같은 상품은 합치고, **DB 가격으로 금액을 계산**해 `pending` 주문과 주문상품을 만든다. 없는 상품/잘못된 수량이면 예외(트랜잭션 전체 취소). 주문명은 `"첫 상품명 외 N건"`.

- `find_guest_order(p_order_id uuid, p_email text) → jsonb` — 비회원 주문 조회. 주문번호와 이메일이 모두 맞고 `pending`이 아닌 비회원 주문만 돌려준다(`user_id`, `payment_key` 제외, `order_items` 포함). anon도 실행 가능.

## 비회원 구매
```
[cart.html] 비회원으로 구매하기 → sb.auth.signInAnonymously() → 임시 계정 세션
  → 주문 확인용 이메일 입력칸 표시 → rpc('create_order', { items, guest_email }) → 이후 결제 흐름은 회원과 동일
[success.html] 비회원이면 주문번호+이메일 조회 안내, guest-order.html 링크
[guest-order.html] rpc('find_guest_order') — 다른 기기/브라우저에서도 조회 가능
```
- 익명 사용자는 `authenticated` 역할이라 기존 RLS(본인 주문만)가 그대로 적용된다.
- 익명 세션은 그 브라우저에만 있으므로 `orders.html`은 같은 브라우저의 비회원 주문만 보여 준다.

## 결제 흐름
```
[cart.html]
  1. TossPayments(clientKey).widgets({ customerKey: user.id })
  2. setAmount(장바구니 합계) → renderPaymentMethods → renderAgreement
  3. [결제하기] → rpc('create_order') → 서버 계산 금액으로 setAmount
  4. requestPayment({ orderId, orderName, successUrl, failUrl })
        │
        ▼ 토스 결제창 (테스트)
        │
  ┌─────┴──────────────┐
  ▼ 성공                ▼ 실패/취소
[success.html?paymentKey&orderId&amount]     [fail.html?code&message]
  5. functions.invoke('confirm-payment')        주문은 pending으로 남음
        │
        ▼ [Edge Function confirm-payment]
  6. JWT로 사용자 확인
  7. 주문 소유자·pending 상태·금액 일치 검증
  8. POST https://api.tosspayments.com/v1/payments/confirm
     (Authorization: Basic base64(TOSS_SECRET_KEY + ":"))
  9. 성공 → orders.status='paid', payment_key/method/approved_at 저장
     실패 → orders.status='failed', 토스 오류 코드/메시지 반환
        │
        ▼
 10. success.html: 장바구니 비우고 결과 표시 (실패 시 fail.html로 이동)
```

## Edge Function `confirm-payment`
- 요청: `POST /functions/v1/confirm-payment`, 헤더 `Authorization: Bearer <사용자 access token>`, 본문 `{ paymentKey, orderId, amount }`
- 응답
  - `200 { order }` — 승인 완료 (이미 같은 paymentKey로 승인된 주문이면 그대로 반환)
  - `401 UNAUTHORIZED` / `400 BAD_REQUEST` / `404 NOT_FOUND`(남의 주문 포함) / `400 INVALID_STATUS` / `400 AMOUNT_MISMATCH`
  - 토스 오류 시 토스의 상태코드와 `{ code, message }`
- 환경변수: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`(기본 제공), `TOSS_SECRET_KEY`(비밀값)
- `verify_jwt: true`로 배포

## Auth 설정
- 이메일 인증 끔 (`mailer_autoconfirm: true`), 비밀번호 최소 6자
- 익명 로그인 켬 (`external_anonymous_users_enabled: true`, IP당 시간당 30회 제한)
- `site_url`: `https://jhhan-git.github.io/goods-shop/`
- 관리자 계정 `admin@admin.com`은 Admin API로 생성 후 `admins`에 등록
