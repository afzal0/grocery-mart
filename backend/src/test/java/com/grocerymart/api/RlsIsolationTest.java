package com.grocerymart.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import javax.sql.DataSource;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Proves the RLS tenant-isolation baseline (NFR-ISO-01). RLS only constrains
 * non-superuser roles, so each transaction first {@code SET ROLE grocery_app}
 * (the least-privilege app role) before setting the tenant GUC — the same posture
 * the API will use in production. A shop-scoped connection sees only that shop's
 * rows, an unscoped one sees nothing, and a write outside the active tenant is
 * rejected by the policy's WITH CHECK.
 */
@SpringBootTest
class RlsIsolationTest {

    private static final String SHOP_A = "11111111-1111-1111-1111-111111111111";
    private static final String SHOP_B = "22222222-2222-2222-2222-222222222222";

    @Autowired
    DataSource dataSource;

    private long countScopedTo(String shopId) throws Exception {
        try (Connection c = dataSource.getConnection()) {
            c.setAutoCommit(false);
            try (Statement st = c.createStatement()) {
                st.execute("SET ROLE grocery_app");
                st.execute("SET LOCAL app.current_shop_id = '" + shopId + "'");
                try (ResultSet rs = st.executeQuery("SELECT count(*) FROM tenant_demo")) {
                    rs.next();
                    long n = rs.getLong(1);
                    c.rollback();
                    return n;
                }
            }
        }
    }

    @Test
    void tenantSeesOnlyItsOwnRows() throws Exception {
        assertEquals(1, countScopedTo(SHOP_A), "shop A should see exactly its 1 row");
        assertEquals(1, countScopedTo(SHOP_B), "shop B should see exactly its 1 row");
    }

    @Test
    void noTenantContextSeesNothing() throws Exception {
        try (Connection c = dataSource.getConnection()) {
            c.setAutoCommit(false);
            try (Statement st = c.createStatement()) {
                st.execute("SET ROLE grocery_app");
                try (ResultSet rs = st.executeQuery("SELECT count(*) FROM tenant_demo")) {
                    rs.next();
                    assertEquals(0, rs.getLong(1), "no tenant GUC -> deny-by-default (0 rows)");
                    c.rollback();
                }
            }
        }
    }

    @Test
    void cannotWriteOutsideActiveTenant() throws Exception {
        try (Connection c = dataSource.getConnection()) {
            c.setAutoCommit(false);
            try (Statement st = c.createStatement()) {
                st.execute("SET ROLE grocery_app");
                st.execute("SET LOCAL app.current_shop_id = '" + SHOP_A + "'");
                assertThrows(Exception.class, () -> st.execute(
                    "INSERT INTO tenant_demo (shop_id, label) VALUES ('" + SHOP_B + "', 'cross-tenant write')"),
                    "WITH CHECK must reject a write for another tenant");
                c.rollback();
            }
        }
    }
}
