// 모든 페이지에서 쓰는 공통 기능: Supabase 연결, 로그인 확인, 상단 메뉴, 도우미 함수
const sb = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_KEY);

async function getUser() {
  const { data: { session } } = await sb.auth.getSession();
  return session ? session.user : null;
}

// 비회원(익명 로그인) 사용자인지
function isGuest(user) {
  return !!(user && user.is_anonymous);
}

async function isAdmin() {
  const { data, error } = await sb.rpc("is_admin");
  return !error && data === true;
}

// 로그인이 안 되어 있으면 로그인 페이지로 보내고, 로그인 후 지금 페이지로 돌아오게 한다.
async function requireLogin() {
  const user = await getUser();
  if (!user) {
    const next = location.pathname.split("/").pop() + location.search;
    location.replace("login.html?next=" + encodeURIComponent(next));
    return new Promise(() => {}); // 페이지 이동 중에는 아래 코드가 실행되지 않게 멈춘다
  }
  return user;
}

function won(n) {
  return Number(n).toLocaleString("ko-KR") + "원";
}

function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function formatDate(iso) {
  if (!iso) return "-";
  return new Date(iso).toLocaleString("ko-KR", { dateStyle: "medium", timeStyle: "short" });
}

const STATUS_LABEL = { paid: "결제 완료", pending: "결제 대기", failed: "결제 실패" };

function statusBadge(status) {
  return `<span class="badge badge-${esc(status)}">${esc(STATUS_LABEL[status] || status)}</span>`;
}

function toast(message) {
  let el = document.getElementById("toast");
  if (!el) {
    el = document.createElement("div");
    el.id = "toast";
    el.className = "toast";
    document.body.appendChild(el);
  }
  el.textContent = message;
  el.classList.add("show");
  clearTimeout(el._timer);
  el._timer = setTimeout(() => el.classList.remove("show"), 1800);
}

// 상단 메뉴 그리기
async function renderNav() {
  const nav = document.getElementById("nav");
  if (!nav) return;
  const user = await getUser();
  const guest = isGuest(user);
  const member = user && !guest;
  const admin = member ? await isAdmin() : false;
  const here = location.pathname.split("/").pop() || "index.html";
  const link = (href, label) =>
    `<a href="${href}" class="${here === href ? "active" : ""}">${label}</a>`;

  nav.innerHTML = `
    <a href="index.html" class="logo">🛍️ 굿즈샵</a>
    <div class="nav-links">
      ${link("index.html", "상품")}
      ${link("cart.html", `장바구니 <span id="cart-count" class="count" hidden></span>`)}
      ${member ? link("orders.html", "내 결제 내역") : ""}
      ${guest ? link("orders.html", "비회원 주문 내역") : ""}
      ${!member ? link("guest-order.html", "비회원 주문 조회") : ""}
      ${admin ? link("admin.html", "관리자") : ""}
      ${member
        ? `<span class="user-email">${esc(user.email)}</span><button id="logout-btn" class="btn btn-small btn-ghost">로그아웃</button>`
        : link("login.html", "로그인")}
    </div>`;
  updateCartBadge();

  const logout = document.getElementById("logout-btn");
  if (logout) {
    logout.addEventListener("click", async () => {
      await sb.auth.signOut();
      location.href = "index.html";
    });
  }
}

document.addEventListener("DOMContentLoaded", renderNav);
