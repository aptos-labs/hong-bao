module addr::dirichlet {

    use aptos_std::math_fixed::{mul_div, ln_plus_32ln2};
    use std::fixed_point32::{Self, FixedPoint32};
    use aptos_framework::randomness;
    use aptos_std::math_fixed;

    friend addr::hongbao;

    const LN2_X_32: u64 = 32 * 2977044472; // 32 * ln(2) in fixed 32 representation

    public(friend) fun sequential_dirichlet_hongbao(
        remaining_amount: u64, remaining_packets: u64
    ): u64 {
        // Use stick breaking construction - Beta(1,a) where a is remaining_packets
        // For each draw, take Beta(1,a) portion of remaining

        // Convert random to FixedPoint32 between 0 and 1
        let u =
            fixed_point32::create_from_rational(
                (randomness::u32_integer() as u64), 0xFFFFFFFF
            );

        let current_exp = {
            let raw_exp = generate_exponential(u);
            if (remaining_packets == 2) {
                // Only adjust for the second-to-last position
                let scale = fixed_point32::create_from_rational(9, 10); // 0.9
                math_fixed::mul_div(fixed_point32::create_from_u64(1), raw_exp, scale)
            } else {
                raw_exp
            }
        };

        // Use n-1 for remaining positions as it worked well for most positions
        let remaining_exp = fixed_point32::create_from_u64(remaining_packets - 1);

        // Calculate proportion
        let total =
            fixed_point32::create_from_raw_value(
                current_exp.get_raw_value() + remaining_exp.get_raw_value()
            );
        let proportion =
            math_fixed::mul_div(
                fixed_point32::create_from_u64(1u64), current_exp, total
            );

        // Calculate amount
        let amount = fixed_point32::multiply_u64(remaining_amount, proportion);

        // Ensure at least 1 token per packet
        if (amount >= remaining_amount - (remaining_packets - 1)) {
            amount = remaining_amount - (remaining_packets - 1);
        };
        if (amount == 0) {
            amount = 1;
        };

        amount
    }

    fun generate_exponential(u: FixedPoint32): FixedPoint32 {
        let one = fixed_point32::create_from_u64(1);
        let complement = fixed_point32::create_from_rational(1, 1);
        let one_minus_u = mul_div(complement, one, u);

        // This gives us ln(1-u) + 32ln(2)
        let ln_plus_offset = ln_plus_32ln2(one_minus_u);

        // Need to subtract 32ln(2) to get just ln(1-u)
        let offset = fixed_point32::create_from_raw_value(LN2_X_32);
        let actual_ln =
            fixed_point32::create_from_raw_value(
                ln_plus_offset.get_raw_value() - offset.get_raw_value()
            );

        // Negate to get -ln(1-u)
        mul_div(actual_ln, complement, one)
    }

    #[test_only]
    use aptos_std::debug::print;
    #[test_only]
    use std::vector;
    #[test_only]
    use aptos_std::string_utils;

    #[test_only]
    fun multiple_sequential_dirichlet_hongbao(
        num_draws: u64, total_amount: u64, num_packets: u64
    ): vector<u64> {
        let result = vector::empty();
        let remaining_money = total_amount;
        let remaining_draws = num_packets;
        for (i in 0..num_draws) {
            let draw = sequential_dirichlet_hongbao(remaining_money, remaining_draws);
            result.push_back(draw);
            if (draw > remaining_money) {
                draw = remaining_money;
            };
            remaining_money = remaining_money - draw;
            remaining_draws = remaining_draws - 1;
        };
        result
    }

    #[test_only]
    fun initialize(aptos_framework: &signer) {
        randomness::initialize_for_testing(aptos_framework);
    }

    #[test(aptos_framework = @aptos_framework)]
    #[lint::allow_unsafe_randomness]
    public fun test_sequential_dirichlet_hongbao(aptos_framework: &signer) {
        initialize(aptos_framework);
        let total_amount: u64 = 1000;
        let num_packets: u64 = 10;
        for (i in 0..10) {
            let amounts =
                multiple_sequential_dirichlet_hongbao(
                    num_packets, total_amount, num_packets
                );
            assert!(amounts.length() == num_packets);
            let sum = 0;
            amounts.for_each(|amount| {
                sum = sum + amount;
            });

            if (sum != total_amount) {
                print(&string_utils::format1(&b"amounts: {}", amounts));
                print(
                    &string_utils::format2(
                        &b"sum: {}, total_amount: {}", sum, total_amount
                    )
                );
            };
            assert!(total_amount - sum < 2);
        };
    }

    #[test(aptos_framework = @aptos_framework)]
    #[lint::allow_unsafe_randomness]
    public fun test_print_many_dirichlet_hongbao(aptos_framework: &signer) {
        initialize(aptos_framework);
        let test_runs = 1;
        let total_amount: u64 = 3250;
        let num_packets: u64 = 3;

        for (i in 0..test_runs) {
            let amounts =
                multiple_sequential_dirichlet_hongbao(
                    num_packets, total_amount, num_packets
                );
            print(&string_utils::format1(&b"amounts: {}", amounts));
        };
    }
}
