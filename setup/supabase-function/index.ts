// Family Hub 알림 보내기 (Supabase Edge Function 이름: fh-push)
// DB 함수 fh_notify 가 x-push-secret 헤더와 함께 호출합니다.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== Deno.env.get("PUSH_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const { title, body, url, subs } = await req.json();
  webpush.setVapidDetails("mailto:familyhub@example.com", Deno.env.get("VAPID_PUBLIC_KEY")!, Deno.env.get("VAPID_PRIVATE_KEY")!);
  const payload = JSON.stringify({ title, body, url });
  const gone: string[] = [];
  let sent = 0;
  await Promise.all((subs || []).map(async (s: { endpoint: string; p256dh: string; auth: string }) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400, urgency: "high" });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) gone.push(s.endpoint);   // 지운 앱·만료된 구독 정리
    }
  }));
  if (gone.length) {
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    await sb.from("push_subs").delete().in("endpoint", gone);
  }
  return Response.json({ sent, gone: gone.length });
});
