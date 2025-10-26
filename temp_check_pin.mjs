import bcrypt from 'bcrypt';
const hash = '.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi';
const pins = ['0000','1234','1111','9999','password','owner','000000'];
for (const pin of pins) {
  const match = await bcrypt.compare(pin, hash);
  if (match) {
    console.log(Match: );
  }
}
