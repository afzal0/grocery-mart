package com.grocerymart.api.config;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.List;

import javax.sql.DataSource;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.datasource.ConnectionHolder;
import org.springframework.jdbc.datasource.DataSourceUtils;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.filter.OncePerRequestFilter;

import com.grocerymart.api.identity.JwtService;

import io.jsonwebtoken.Claims;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * Activates Postgres Row-Level Security for the running app. When {@code grocerymart.rls.enforce=true},
 * each AUTHENTICATED request is executed under the non-bypass {@code grocery_app} role with the
 * {@code app.current_user_id} / {@code app.current_role} GUCs set from the JWT, so the V015 policies
 * enforce tenant isolation at the database layer (defense in depth behind the app-layer checks).
 *
 * <p>The bound connection is reused by every JdbcTemplate call on the request thread (via
 * {@link DataSourceUtils}/{@link TransactionSynchronizationManager}), so non-transactional reads are
 * covered too. Unauthenticated requests (login / refresh / OTP / ping) are intentionally left on the
 * bypass {@code postgres} role so the auth flow can read {@code app_user}/{@code refresh_token} before
 * a user context exists.
 *
 * <p><b>DEFAULT OFF.</b> Enabling requires that every authenticated query path be covered by a policy
 * (V015). Validate in staging before enabling in production; the flag is the instant rollback.
 */
@Component
@Order(2)   // after RateLimitFilter(@Order 1); parses the JWT itself, independent of SecurityContext
public class RlsConnectionFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(RlsConnectionFilter.class);

    private final DataSource dataSource;
    private final JwtService jwt;
    private final boolean enforce;

    public RlsConnectionFilter(DataSource dataSource, JwtService jwt,
            @Value("${grocerymart.rls.enforce:false}") boolean enforce) {
        this.dataSource = dataSource;
        this.jwt = jwt;
        this.enforce = enforce;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        Principal p = enforce ? principal(request) : null;
        if (p == null) {              // disabled, or unauthenticated -> run as the connecting (bypass) role
            chain.doFilter(request, response);
            return;
        }
        Connection con = DataSourceUtils.getConnection(dataSource);
        boolean bound = false;
        try {
            try (Statement st = con.createStatement()) {
                st.execute("SET ROLE grocery_app");
            }
            try (PreparedStatement ps = con.prepareStatement(
                    "SELECT set_config('app.current_user_id', ?, false), set_config('app.current_role', ?, false)")) {
                ps.setString(1, p.userId());
                ps.setString(2, p.role());
                ps.execute();
            }
            if (!TransactionSynchronizationManager.hasResource(dataSource)) {
                TransactionSynchronizationManager.bindResource(dataSource, new ConnectionHolder(con));
                bound = true;
            }
            chain.doFilter(request, response);
        } catch (ServletException | IOException e) {
            throw e;
        } catch (Exception e) {
            throw new ServletException(e);
        } finally {
            if (bound) {
                TransactionSynchronizationManager.unbindResource(dataSource);
            }
            resetAndRelease(con);
        }
    }

    private void resetAndRelease(Connection con) {
        try (Statement st = con.createStatement()) {
            st.execute("RESET app.current_user_id");
            st.execute("RESET app.current_role");
            st.execute("RESET ROLE");
        } catch (Exception e) {
            log.warn("Failed to reset RLS connection state before release", e);
        }
        DataSourceUtils.releaseConnection(con, dataSource);
    }

    private Principal principal(HttpServletRequest req) {
        String h = req.getHeader("Authorization");
        if (h == null || !h.startsWith("Bearer ")) return null;
        try {
            Claims c = jwt.parse(h.substring(7));
            @SuppressWarnings("unchecked")
            List<String> roles = c.get("roles", List.class);
            String sub = c.getSubject();
            if (sub == null) return null;
            return new Principal(sub, primaryRole(roles));
        } catch (Exception e) {
            return null;   // invalid token -> treat as unauthenticated (no role switch)
        }
    }

    private static String primaryRole(List<String> roles) {
        if (roles == null || roles.isEmpty()) return "CUSTOMER";
        if (roles.contains("ADMIN")) return "ADMIN";
        return roles.get(0);
    }

    private record Principal(String userId, String role) {}
}
