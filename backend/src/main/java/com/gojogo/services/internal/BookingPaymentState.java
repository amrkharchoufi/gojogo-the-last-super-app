package com.gojogo.services.internal;

/** Where a booking's money is. Uniquely named per the incidents log — both
 *  delivery and economy already carry payment-state enums of their own. */
enum BookingPaymentState { NONE, HELD, SETTLED, RELEASED }
