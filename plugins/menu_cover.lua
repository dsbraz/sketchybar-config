-- Grow immediately; only shrink after the new app/menu width stays stable.
local M = {}
M.settleTime = 0.4

function M.update(state, width, appID, now)
  if not state.width or width >= state.width then
    state.width = width
    state.pending = nil
    return width
  end

  local pending = state.pending
  if not pending or pending.width ~= width or pending.appID ~= appID then
    pending = { width = width, appID = appID, since = now }
    state.pending = pending
  end

  local remaining = M.settleTime - (now - pending.since)
  if remaining <= 0 then
    state.width = width
    state.pending = nil
    return width
  end
  return state.width, remaining
end

return M
