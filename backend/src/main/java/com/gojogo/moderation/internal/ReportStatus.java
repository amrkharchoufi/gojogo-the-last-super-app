package com.gojogo.moderation.internal;

/** Where a report is: waiting on a person, acted on, or judged to be nothing. */
enum ReportStatus {

    OPEN,
    ACTIONED,
    DISMISSED
}
