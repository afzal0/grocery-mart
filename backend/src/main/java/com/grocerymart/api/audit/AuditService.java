package com.grocerymart.api.audit;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import tools.jackson.databind.ObjectMapper;

/**
 * Epic 9 (Story 9.11): append-only audit trail for sensitive actions — merges, payouts, role
 * changes, deletions, privileged cross-tenant reads, and DENIED attempts. No update/delete path
 * exists in the application; the retention purge (9.8) is the sole exception.
 */
@Service
public class AuditService {

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    public AuditService(JdbcTemplate jdbc, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    public void log(UUID actorId, String action, String targetType, String targetId,
                    Map<String, Object> before, Map<String, Object> after, String outcome) {
        jdbc.update(
            "INSERT INTO audit_log (actor_id, action, target_type, target_id, before_summary, after_summary, "
            + "source_ip, outcome) VALUES (?, ?, ?, ?, ?::jsonb, ?::jsonb, ?, ?)",
            actorId, action, targetType, targetId,
            before == null ? null : mapper.writeValueAsString(before),
            after == null ? null : mapper.writeValueAsString(after),
            sourceIp(), outcome);
    }

    // REQUIRES_NEW so the audit row commits independently — a DENIED action that rolls back its own
    // transaction must still leave its audit trail (Story 9.11: denied access is not invisible).
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void success(UUID actorId, String action, String targetType, String targetId,
                        Map<String, Object> before, Map<String, Object> after) {
        log(actorId, action, targetType, targetId, before, after, "success");
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void denied(UUID actorId, String action, String targetType, String targetId) {
        log(actorId, action, targetType, targetId, null, null, "denied");
    }

    /** Filterable audit query (access to the log is itself audited by the caller). */
    public List<Map<String, Object>> query(String actor, String action, Integer limit) {
        int lim = Math.min(limit == null ? 100 : limit, 500);
        StringBuilder sql = new StringBuilder(
            "SELECT id, actor_id, action, target_type, target_id, outcome, source_ip, created_at FROM audit_log WHERE 1=1 ");
        java.util.List<Object> args = new java.util.ArrayList<>();
        if (actor != null && !actor.isBlank()) { sql.append("AND actor_id = ? "); args.add(UUID.fromString(actor)); }
        if (action != null && !action.isBlank()) { sql.append("AND action = ? "); args.add(action); }
        sql.append("ORDER BY created_at DESC LIMIT ?"); args.add(lim);
        return jdbc.query(sql.toString(), (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", rs.getLong("id"));
            m.put("actorId", rs.getObject("actor_id") == null ? null : rs.getObject("actor_id").toString());
            m.put("action", rs.getString("action"));
            m.put("targetType", rs.getString("target_type"));
            m.put("targetId", rs.getString("target_id"));
            m.put("outcome", rs.getString("outcome"));
            m.put("sourceIp", rs.getString("source_ip"));
            m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
            return m;
        }, args.toArray());
    }

    private String sourceIp() {
        try {
            ServletRequestAttributes attrs = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
            if (attrs == null) return null;
            var req = attrs.getRequest();
            String fwd = req.getHeader("X-Forwarded-For");
            return (fwd != null && !fwd.isBlank()) ? fwd.split(",")[0].trim() : req.getRemoteAddr();
        } catch (Exception e) {
            return null;
        }
    }
}
