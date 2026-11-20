// ARK STUDY LAB - 상담·이야기방 공통 도우미

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str == null ? '' : String(str);
  return div.innerHTML;
}

// 로그인 + 역할 확인. 허용되지 않은 역할이면 알맞은 페이지로 보냄.
async function talkRequireProfile(allowedRoles) {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) {
    window.location.href = 'login.html';
    return null;
  }
  const { data: profile, error } = await sb
    .from('profiles')
    .select('*')
    .eq('id', session.user.id)
    .single();

  if (error || !profile) {
    document.getElementById('content').innerHTML = '<p>프로필을 불러오지 못했습니다.</p>';
    return null;
  }
  if (profile.account_status === 'suspended') {
    await sb.auth.signOut();
    window.location.href = 'login.html?suspended=1';
    return null;
  }
  if (!allowedRoles.includes(profile.role)) {
    const home = { admin: 'admin.html', parent: 'parent.html', student: 'student.html' };
    window.location.href = home[profile.role] || 'login.html';
    return null;
  }

  const nameEl = document.getElementById('userName');
  if (nameEl) nameEl.textContent = profile.name + '님';

  const logoutBtn = document.getElementById('logoutBtn');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', async () => {
      await sb.auth.signOut();
      window.location.href = 'login.html';
    });
  }
  return profile;
}

// 표(테이블)가 아직 없을 때 안내 문구
function talkSetupError(error) {
  const text = (error && error.message) || '';
  if (/does not exist|schema cache|relation/i.test(text)) {
    return '아직 상담·이야기방 기능이 준비되지 않았어요. (관리자: supabase/021_consult_and_community.sql 실행 필요)';
  }
  return '오류가 발생했어요: ' + escapeHtml(text);
}

function talkTime(iso) {
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const time = d.toLocaleTimeString('ko-KR', { hour: 'numeric', minute: '2-digit' });
  if (sameDay) return '오늘 ' + time;
  return d.toLocaleDateString('ko-KR', { month: 'long', day: 'numeric' }) + ' ' + time;
}

function talkStatusBadge(status, forTeacher) {
  const map = forTeacher
    ? { waiting: ['답변 필요', 'locked'], answered: ['답변함', 'unlocked'], closed: ['마무리', 'muted'] }
    : { waiting: ['답변 기다리는 중', 'locked'], answered: ['선생님 답변 도착', 'unlocked'], closed: ['마무리됨', 'muted'] };
  const [label, cls] = map[status] || [status, 'muted'];
  return `<span class="status-badge ${cls} talk-badge">${label}</span>`;
}

function talkBubble({ mine, who, body, at }) {
  return `
    <div class="talk-bubble-wrap ${mine ? 'mine' : 'theirs'}">
      <div class="talk-who">${escapeHtml(who)} · ${talkTime(at)}</div>
      <div class="talk-bubble">${escapeHtml(body)}</div>
    </div>`;
}
