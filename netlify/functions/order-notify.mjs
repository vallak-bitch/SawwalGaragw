import nodemailer from "nodemailer";

const reply = (body, status=200) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json; charset=utf-8" }
});

export default async (req) => {
  if (req.method !== "POST") return reply({error:"Method not allowed"},405);
  const supplied = req.headers.get("x-webhook-secret") || "";
  const expected = process.env.WEBHOOK_SECRET || "";
  if (!expected || supplied.length !== expected.length) return reply({error:"Unauthorized"},401);
  let mismatch=0;
  for(let i=0;i<supplied.length;i++) mismatch |= supplied.charCodeAt(i)^expected.charCodeAt(i);
  if(mismatch!==0) return reply({error:"Unauthorized"},401);

  try {
    const event = await req.json();
    if(event.type!=="INSERT" || event.table!=="orders" || event.schema!=="public" || !event.record?.id)
      return reply({ignored:true});
    const o=event.record;
    const transporter=nodemailer.createTransport({
      service:"gmail",
      auth:{user:process.env.GMAIL_USER,pass:process.env.GMAIL_APP_PASSWORD}
    });
    const items=(Array.isArray(o.items)?o.items:[]).map((x,i)=>
      `${i+1}. ${String(x.name||"Produk")} (${String(x.variation||"")}) x${Number(x.quantity||0)}`
    ).join("\n") || "-";
    await transporter.sendMail({
      from:`"SAWWAL Store" <${process.env.GMAIL_USER}>`,
      to:process.env.OWNER_EMAIL || "satanteam034@gmail.com",
      subject:`Pesanan baru SAWWAL ${o.id}`,
      text:[
        "PESANAN BARU SAWWAL",`ID: ${o.id}`,`Nama: ${o.customer_name}`,
        `WhatsApp: ${o.customer_phone}`,`Alamat: ${o.address}`,
        `Pembayaran: ${o.payment_method}`,`Produk:\n${items}`,
        `Total: Rp ${Number(o.total||0).toLocaleString("id-ID")}`,
        `Status: ${o.status}`
      ].join("\n\n")
    });
    return reply({success:true});
  } catch(err) {
    console.error("SAWWAL webhook error",err);
    return reply({error:"Email notification failed"},500);
  }
};
