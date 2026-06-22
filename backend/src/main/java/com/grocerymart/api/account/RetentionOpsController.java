package com.grocerymart.api.account;

import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Admin/ops trigger for the retention purge (also runs hourly). Epic 9, Story 9.8. */
@RestController
@RequestMapping("/api/v1/admin/retention")
@PreAuthorize("hasRole('ADMIN')")
public class RetentionOpsController {

    private final RetentionService retention;

    public RetentionOpsController(RetentionService retention) {
        this.retention = retention;
    }

    @PostMapping("/_purge")
    public Map<String, Object> purge() {
        return retention.purge();
    }
}
