/**
 * ARK STUDY LAB - 학부모 코칭 알림 메일 (Google Apps Script)
 *
 * 하는 일:
 *   관리자 화면에서 "학부모님께 보내기"를 누르면 이 스크립트가 호출되어,
 *   그 학생의 학부모 이메일로 "선생님 코칭이 도착했어요" 메일을 보냄.
 *   메일은 이 스크립트를 배포한 구글 계정(Gmail)에서 나감.
 *
 * 보안:
 *   - 비밀 키를 저장하지 않음. 아래 두 값은 홈페이지에 이미 공개된 값.
 *   - 호출한 사람의 로그인 토큰으로 Supabase에 물어봐서
 *     "관리자"이고 "보낸(published) 코칭"이 있을 때만 메일을 보냄.
 *   - 같은 코칭에 대해 중복 메일을 보내지 않음 (수정해서 다시 보내면 다시 발송).
 *
 * 배포: 확장 프로그램 없이 script.google.com 에서
 *   배포 → 새 배포 → 유형: 웹 앱 → 실행: 나 → 액세스 권한: 모든 사용자
 */

const SUPABASE_URL = 'https://ffzwgqqggwnhxigkjsum.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_3qapTyE--7G3G3flR_D9jQ_45eztl_-';
const SITE_URL = 'https://arkstudylabceja.github.io';
const SENDER_NAME = 'ARK STUDY LAB';

function doPost(e) {
  try {
    const req = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    const logId = String(req.log_id || '');
    const token = String(req.access_token || '');
    if (!/^[0-9a-f-]{36}$/i.test(logId) || !token) return reply_({ ok: false, error: 'bad_request' });

    // 1) 호출한 사람이 관리자인지 확인
    const user = authGet_('/auth/v1/user', token);
    if (!user || !user.id) return reply_({ ok: false, error: 'not_logged_in' });
    const me = restGet_(`profiles?id=eq.${user.id}&select=role,account_status`, token)[0];
    if (!me || me.role !== 'admin' || me.account_status === 'suspended') {
      return reply_({ ok: false, error: 'not_admin' });
    }

    // 2) 보낸 코칭이 있는지 확인
    const fb = restGet_(`study_log_feedback?log_id=eq.${logId}&select=body,status,published_at`, token)[0];
    if (!fb || fb.status !== 'published' || !fb.body) return reply_({ ok: false, error: 'not_published' });

    // 같은 코칭에 중복 발송 방지
    const props = PropertiesService.getScriptProperties();
    const sentKey = 'sent_' + logId;
    if (props.getProperty(sentKey) === fb.published_at) return reply_({ ok: true, skipped: true });

    // 3) 기록·학생·학부모 정보
    const log = restGet_(`study_logs?id=eq.${logId}&select=study_date,subject,content,student_id`, token)[0];
    if (!log) return reply_({ ok: false, error: 'log_not_found' });
    const student = restGet_(`profiles?id=eq.${log.student_id}&select=name,parent_email`, token)[0];
    if (!student || !student.parent_email) return reply_({ ok: false, error: 'no_parent_email' });
    const parent = restGet_(`profiles?email=eq.${encodeURIComponent(student.parent_email)}&role=eq.parent&select=name,email`, token)[0];
    const to = parent ? parent.email : student.parent_email;

    // 4) 메일 보내기
    const subject = `[ARK STUDY LAB] ${student.name} 학생의 공부 기록에 선생님 코칭이 도착했어요`;
    const html = `
      <div style="font-family:'Apple SD Gothic Neo','Malgun Gothic',sans-serif;max-width:560px;margin:0 auto;color:#0b1631;line-height:1.7;">
        <p>${esc_(parent ? parent.name : '학부모')}님, 안녕하세요. ARK STUDY LAB입니다.</p>
        <p><b>${esc_(student.name)}</b> 학생이 ${esc_(log.study_date)}에 올린
           ${log.subject ? esc_(log.subject) + ' ' : ''}공부 기록에 선생님 코칭이 도착했어요.</p>
        <div style="background:#f6f7fb;border-radius:10px;padding:12px 16px;margin:14px 0;font-size:14px;color:#6b7280;">
          ${esc_(log.content)}
        </div>
        <div style="background:#fbf3d9;border-left:4px solid #c9a227;border-radius:10px;padding:14px 16px;margin:14px 0;">
          <div style="font-weight:800;margin-bottom:6px;">💬 선생님 코칭</div>
          <div style="white-space:pre-wrap;">${esc_(fb.body)}</div>
        </div>
        <p><a href="${SITE_URL}/parent.html" style="display:inline-block;background:#0b1631;color:#fff;text-decoration:none;padding:10px 18px;border-radius:8px;font-weight:700;">홈페이지에서 공부 사진과 함께 보기</a></p>
        <p style="font-size:12px;color:#6b7280;">이 메일은 선생님이 코칭을 보낼 때 자동으로 발송됩니다.</p>
      </div>`;
    MailApp.sendEmail({ to: to, subject: subject, htmlBody: html, name: SENDER_NAME });
    props.setProperty(sentKey, fb.published_at);
    return reply_({ ok: true });
  } catch (err) {
    return reply_({ ok: false, error: String(err && err.message || err) });
  }
}

function doGet() {
  return reply_({ ok: true, service: 'ARK STUDY LAB parent notify' });
}

function restGet_(path, token) {
  return authGet_('/rest/v1/' + path, token) || [];
}

function authGet_(path, token) {
  const res = UrlFetchApp.fetch(SUPABASE_URL + path, {
    method: 'get',
    headers: { apikey: SUPABASE_PUBLISHABLE_KEY, Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });
  if (res.getResponseCode() >= 300) return null;
  return JSON.parse(res.getContentText());
}

function esc_(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function reply_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

// 처음 배포할 때 권한 승인을 받기 위해 한 번 실행하는 함수 (메일을 실제로 보내지 않음)
function authorize() {
  MailApp.getRemainingDailyQuota();
  UrlFetchApp.fetch(SUPABASE_URL + '/auth/v1/health', {
    headers: { apikey: SUPABASE_PUBLISHABLE_KEY }, muteHttpExceptions: true
  });
}
