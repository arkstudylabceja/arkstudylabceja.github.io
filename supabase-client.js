// ARK STUDY LAB - Supabase 연결 설정
// (이 값들은 브라우저에 노출되어도 안전한 공개 키입니다)
const SUPABASE_URL = "https://acxwwvrkxrbsvfxheflj.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_POFPr4WoBqWaTBgUt58Zow_VN_lCrsL";

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
