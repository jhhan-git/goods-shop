// 결제 승인 서버 함수
// 토스 결제창에서 돌아온 결제를 검증하고, 토스 결제 승인 API를 호출한 뒤 주문 상태를 저장한다.
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ message: "POST 요청만 받아요" }, 405);

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. 누가 요청했는지 확인
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await admin.auth.getUser(token);
    if (!user) return json({ code: "UNAUTHORIZED", message: "로그인이 필요해요" }, 401);

    const { paymentKey, orderId, amount } = await req.json();
    if (typeof paymentKey !== "string" || typeof orderId !== "string" || amount == null) {
      return json({ code: "BAD_REQUEST", message: "결제 정보가 부족해요" }, 400);
    }

    // 2. 주문이 본인 것인지, 아직 결제 전인지, 금액이 맞는지 확인
    const { data: order } = await admin.from("orders").select("*").eq("id", orderId).maybeSingle();
    if (!order || order.user_id !== user.id) {
      return json({ code: "NOT_FOUND", message: "주문을 찾을 수 없어요" }, 404);
    }
    if (order.status === "paid" && order.payment_key === paymentKey) {
      return json({ order }); // 새로고침 등으로 다시 요청한 경우
    }
    if (order.status !== "pending") {
      return json({ code: "INVALID_STATUS", message: "이미 처리된 주문이에요" }, 400);
    }
    if (Number(amount) !== order.total_amount) {
      return json({ code: "AMOUNT_MISMATCH", message: "결제 금액이 주문 금액과 달라요" }, 400);
    }

    // 3. 토스 결제 승인 API 호출 (시크릿 키 뒤에 ':'를 붙여 Base64 인코딩)
    const secretKey = Deno.env.get("TOSS_SECRET_KEY")!;
    const tossRes = await fetch("https://api.tosspayments.com/v1/payments/confirm", {
      method: "POST",
      headers: {
        Authorization: "Basic " + btoa(secretKey + ":"),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ paymentKey, orderId, amount: order.total_amount }),
    });
    const toss = await tossRes.json();

    // 4. 결과 저장
    if (!tossRes.ok) {
      await admin.from("orders").update({ status: "failed" }).eq("id", orderId).eq("status", "pending");
      return json({ code: toss.code, message: toss.message }, tossRes.status);
    }

    const { data: updated } = await admin
      .from("orders")
      .update({
        status: "paid",
        payment_key: toss.paymentKey,
        payment_method: toss.method ?? null,
        approved_at: toss.approvedAt ?? new Date().toISOString(),
      })
      .eq("id", orderId)
      .select()
      .single();

    return json({ order: updated });
  } catch (e) {
    return json({ code: "SERVER_ERROR", message: String(e) }, 500);
  }
});
