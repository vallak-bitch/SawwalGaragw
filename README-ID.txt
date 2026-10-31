SAWWAL — PAKET DEPLOY NETLIFY + SUPABASE

PAKET INI SUDAH MEMASUKKAN DESAIN ASLI TOKO ONLINE SAWWAL DAN MENGHUBUNGKAN:
- Frontend asli SAWWAL: public/index.html
- Database Supabase + RLS: supabase/schema.sql
- Checkout server-side: public.create_order() (harga dan stok dihitung di database)
- Login owner: Supabase Auth + daftar owner private.owner_users
- Email webhook: Netlify Function netlify/functions/order-notify.mjs

LANGKAH WAJIB (cukup sekali, lewat browser Android):

1) AMANKAN KEY
Secret Key Supabase pernah dibagikan di percakapan. Segera rotasi di Supabase Dashboard > Project Settings > API Keys. Jangan masukkan secret key ke file HTML/GitHub.
Publishable key boleh berada di frontend. Publishable Key project yang kamu berikan sudah dimasukkan ke public/index.html. Jika kamu merotasi Publishable Key juga, ganti nilai tersebut dengan key aktif yang baru. Jangan gunakan secret key.

2) BUAT OWNER
Supabase Dashboard > Authentication > Users > Add user.
Email: satanteam034@gmail.com
Buat password kuat sendiri. Jangan gunakan password yang pernah ditulis dalam kode lama.
Pastikan user dibuat sebelum SQL dijalankan.

3) DATABASE
Buka Supabase SQL Editor:
https://supabase.com/dashboard/project/ljpqdhkeakghgoyibrma/sql/new
Buka supabase/schema.sql dari ZIP, salin semua SQL, lalu Run.
SQL akan mendaftarkan user yang email-nya satanteam034@gmail.com sebagai owner.
Jika SQL pernah dijalankan sebelum akun owner dibuat, jalankan ulang blok:
insert into private.owner_users(user_id)
select id from auth.users where lower(email)=lower('satanteam034@gmail.com')
on conflict (user_id) do nothing;

4) UPLOAD KE GITHUB
Ekstrak ZIP di HP. Buka https://github.com/new dan buat repository baru, misalnya sawwal-store.
Upload semua ISI folder SAWWAL-NETLIFY-READY ke root repository. Pastikan file netlify.toml, package.json, public/, supabase/, netlify/ ada di root repository.

5) DEPLOY NETLIFY
Buka https://app.netlify.com/
Add new site > Import an existing project > GitHub > pilih repository sawwal-store.
Build command: kosongkan.
Publish directory: public
Deploy site.
Netlify akan mendeteksi netlify.toml dan menginstal nodemailer untuk Function.
Jangan gunakan Netlify Drop untuk paket ini: deploy drag-and-drop statis tidak membangun Netlify Functions.

6) EMAIL GMAIL
Aktifkan 2-Step Verification di Google Account.
Buat App Password: https://myaccount.google.com/apppasswords
Di Netlify Site configuration > Environment variables, tambahkan:
GMAIL_USER = alamat Gmail pengirim
GMAIL_APP_PASSWORD = App Password Gmail (bukan password login)
OWNER_EMAIL = satanteam034@gmail.com
WEBHOOK_SECRET = string acak panjang (minimal 32 karakter), contoh buat sendiri.
Jangan simpan nilai rahasia ini di GitHub atau HTML. Setelah menambahkan, trigger redeploy.

7) HUBUNGKAN SUPABASE DATABASE WEBHOOK
Supabase > Database > Webhooks > Create webhook.
Table: public.orders
Event: INSERT
Method: POST
URL: https://NAMA-SITE-ANDA.netlify.app/.netlify/functions/order-notify
Header:
x-webhook-secret = nilai WEBHOOK_SECRET yang sama persis dengan Netlify.
Simpan.

8) UJI COBA
- Buka URL Netlify.
- Tambah produk ke keranjang dan checkout. Database menghitung harga dan mengurangi stok.
- Cek row baru di Supabase > Table Editor > orders.
- Cek Gmail owner.
- Klik Owner pada website, login dengan akun Auth owner.
- Dashboard owner dapat membaca orders dan mengelola produk. RLS memblokir akun lain.

CATATAN:
- Nomor WhatsApp, informasi rekening, alamat, dan teks toko masih mengikuti isi file HTML asal. Periksa melalui pengaturan website sebelum dipublikasikan.
- Kategori, banner, pengaturan tampilan dan sebagian modul pelanggan pada HTML asal masih berupa state browser, belum dipindahkan ke tabel cloud.
- Modul pembayaran gateway belum dibuat; metode transfer/konfirmasi WA bukan bukti pembayaran otomatis.
- Supabase dan Netlify free tier memiliki kuota dan ketentuan provider. Ini bukan VPS unlimited, tetapi website/backend serverless bisa diakses online selama layanan aktif.
