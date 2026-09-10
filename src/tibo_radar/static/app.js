const $ = (id) => document.getElementById(id);

const levelNames = {
  green: "正常使用",
  yellow: "开始关注",
  orange: "高关注：可以准备开蹬",
  red: "很可能：留意明确落地时间",
};

const fmtTime = (value) => {
  if (!value) return "时间未知";
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
};

const setWidth = (id, value) => {
  $(id).style.width = `${Math.max(2, Math.min(100, value))}%`;
};

function render(data) {
  $("hero").dataset.level = data.level;
  $("level-label").textContent = levelNames[data.level] || data.level_label;
  $("combined-24").textContent = data.combined_24h;
  $("combined-48").textContent = `${data.combined_48h}%`;
  $("likely-window").textContent = data.likely_window;
  $("confidence").textContent = `${data.confidence}${data.stale ? " · 缓存" : ""}`;

  $("global-24").textContent = `${data.global_24h}%`;
  $("global-48").textContent = `${data.global_48h}%`;
  $("banked-24").textContent = `${data.banked_24h}%`;
  $("banked-48").textContent = `${data.banked_48h}%`;
  setWidth("global-bar", data.global_24h);
  setWidth("banked-bar", data.banked_24h);

  const conditional = data.affected_user_banked_24h !== null;
  $("conditional-card").hidden = !conditional;
  if (conditional) {
    $("affected-24").textContent = `${data.affected_user_banked_24h}%`;
    setWidth("affected-bar", data.affected_user_banked_24h);
  }

  $("freshness").textContent = data.data_updated_at
    ? `数据 ${fmtTime(data.data_updated_at)}`
    : "数据时间未知";
  $("generated-at").textContent = `计算于 ${fmtTime(data.generated_at)}`;

  $("evidence").replaceChildren(...data.evidence.map((item) => {
    const li = document.createElement("li");
    const sign = item.delta ? `<em class="${item.delta > 0 ? "up" : "down"}">${item.delta > 0 ? "+" : ""}${item.delta}</em>` : "";
    li.innerHTML = `<div><strong>${escapeHtml(item.label)}</strong>${sign}</div><p>${escapeHtml(item.detail)}</p>`;
    if (item.source_url) {
      const a = document.createElement("a");
      a.href = item.source_url;
      a.target = "_blank";
      a.rel = "noopener";
      a.textContent = "来源 ↗";
      li.appendChild(a);
    }
    return li;
  }));

  $("events").replaceChildren(...data.latest_events.map((event) => {
    const li = document.createElement("li");
    const content = document.createElement(event.source_url ? "a" : "div");
    if (event.source_url) {
      content.href = event.source_url;
      content.target = "_blank";
      content.rel = "noopener";
    }
    content.innerHTML = `<span class="event-kind">${escapeHtml(event.kind)}</span><time>${fmtTime(event.occurred_at)}</time><p>${escapeHtml(event.title)}</p>`;
    li.appendChild(content);
    return li;
  }));

  const notice = $("notice");
  if (data.source_errors.length) {
    notice.hidden = false;
    notice.textContent = `部分数据源异常：${data.source_errors.join("；")}`;
  } else {
    notice.hidden = true;
  }
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

async function refresh(force = false) {
  const button = $("refresh");
  button.disabled = true;
  button.textContent = "正在刷新…";
  try {
    const response = await fetch(force ? "/api/refresh" : "/api/snapshot", { cache: "no-store" });
    const data = await response.json();
    if (!response.ok) throw new Error(data.detail || data.error || "unknown error");
    render(data);
  } catch (error) {
    const notice = $("notice");
    notice.hidden = false;
    notice.textContent = `暂时无法刷新：${error.message}`;
  } finally {
    button.disabled = false;
    button.textContent = "刷新信号";
  }
}

$("refresh").addEventListener("click", () => refresh(true));
refresh(false);
setInterval(() => refresh(false), 120000);

