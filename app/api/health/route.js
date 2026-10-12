// Health check. The Telegram bot webhook and the database link will live under /api next to this.
export async function GET() {
  return Response.json({ ok: true, app: 't2r-lab-web', time: new Date().toISOString() });
}
