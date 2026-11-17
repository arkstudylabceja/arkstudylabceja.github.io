// ARK STUDY LAB - 학습 기록 공통 기능
// 1) 사진 자동 줄이기 (업로드 전에 브라우저에서 처리)
// 2) 선생님 코칭 피드백 불러오기·보여주기

const PHOTO_MAX_SIDE = 1600;      // 긴 변 최대 픽셀
const PHOTO_QUALITY = 0.8;        // JPEG 품질
const PHOTO_MAX_BYTES = 5 * 1024 * 1024;   // 저장소 제한(5MB)
const PHOTO_RAW_MAX_BYTES = 30 * 1024 * 1024; // 줄이기 전 원본 허용 크기

// 사진을 긴 변 1600px, JPEG로 줄여서 돌려줌.
// 줄일 수 없는 형식이면 원본을 그대로 돌려줌.
async function shrinkPhoto(file) {
  if (!file || !file.type.startsWith('image/') || file.type === 'image/gif') return file;
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    const w = img.naturalWidth;
    const h = img.naturalHeight;
    if (!w || !h) return file;
    const scale = Math.min(1, PHOTO_MAX_SIDE / Math.max(w, h));
    const cw = Math.round(w * scale);
    const ch = Math.round(h * scale);
    const canvas = document.createElement('canvas');
    canvas.width = cw;
    canvas.height = ch;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, cw, ch);
    ctx.drawImage(img, 0, 0, cw, ch);
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', PHOTO_QUALITY));
    if (!blob) return file;
    // 이미 작은 JPEG라 더 커졌다면 원본 사용
    if (blob.size >= file.size && file.type === 'image/jpeg') return file;
    return new File([blob], 'photo.jpg', { type: 'image/jpeg' });
  } catch (e) {
    return file;
  } finally {
    URL.revokeObjectURL(url);
  }
}

// 피드백을 붙여서 기록을 불러옴.
// (피드백 표가 아직 없으면 피드백 없이라도 기록은 보이도록 한 번 더 시도)
async function selectLogsWithFeedback(buildQuery, baseColumns, feedbackColumns) {
  const cols = feedbackColumns || 'body, status, published_at';
  const withFeedback = await buildQuery(`${baseColumns}, study_log_feedback(${cols})`);
  if (!withFeedback.error) return withFeedback;
  return buildQuery(baseColumns);
}

// 기록에 붙은 피드백 꺼내기 (한 개 또는 배열 모두 처리)
function feedbackOf(log) {
  const fb = log && log.study_log_feedback;
  if (!fb) return null;
  return Array.isArray(fb) ? (fb[0] || null) : fb;
}

function feedbackEscape(str) {
  const div = document.createElement('div');
  div.textContent = str == null ? '' : String(str);
  return div.innerHTML;
}

// 학부모 화면용: 보낸 피드백 보여주기
function renderPublishedFeedback(log) {
  const fb = feedbackOf(log);
  if (!fb || fb.status !== 'published' || !fb.body) return '';
  const date = fb.published_at ? new Date(fb.published_at).toLocaleDateString('ko-KR') : '';
  return `
    <div class="feedback-box">
      <div class="feedback-title">💬 선생님 코칭${date ? ` <span>${date}</span>` : ''}</div>
      <div class="feedback-body">${feedbackEscape(fb.body)}</div>
    </div>`;
}
