module addr::dirichlet {

    use aptos_std::math_fixed::{mul_div, ln_plus_32ln2};
    use std::fixed_point32::{Self, FixedPoint32};
    use aptos_framework::randomness;
    use std::vector;

    friend addr::hongbao;

    /// 1/ln(2) * 10
    const LOG2_E_x10: u64 = 14426950408889634;
    const MAX_U32: u32 = 4_294_967_295u32;

    ///     Sequential Dirichlet construction using Gamma variables.
    ///     Each draw is independent and normalized at the end.
    ///     Key insight: If X_1,...,X_n ~ Gamma(alpha_i, 1) independently,
    ///     then (X_1/S,...,X_n/S) ~ Dirichlet(alpha_1,...,alpha_n) where S = sum(X_i)
    public(friend) fun sequential_dirichlet_hongbao(total_amount: u64, num_packets: u64): FixedPoint32 {
        // Use exponential distribution (Gamma with alpha=1) for simplicity
        let draws: vector<FixedPoint32> = vector::empty();
        let running_sum: FixedPoint32 = fixed_point32::create_from_u64(0);

        // Phase 1: Sequential gamma draws
        for (i in 0..num_packets ) {
            // Exponential is just Gamma(1,1)
            let random = randomness::u32_integer();
            // Scale random down by max u32, so it's 0->1
            let random = fixed_point32::create_from_rational((random as u64), (MAX_U32 as u64));

            let draw = generate_exponential(random);
            draws.push_back(draw);
            running_sum = fixed_point32::create_from_raw_value(
                running_sum.get_raw_value() +
                    draw.get_raw_value()
            );
        };

        // Phase 2: Normalize and scale
        let total = fixed_point32::create_from_u64(total_amount);

        mul_div(draws[0], total, running_sum)
    }

    fun generate_exponential(u: FixedPoint32): FixedPoint32 {
        let one = fixed_point32::create_from_u64(1);
        let complement = fixed_point32::create_from_rational(1, 1);
        let one_minus_u = mul_div(complement, one, u);

        // This gives us ln(1-u) + 32ln(2)
        let ln_plus_offset = ln_plus_32ln2(one_minus_u);

        // Need to subtract 32ln(2) to get just ln(1-u)
        let offset = fixed_point32::create_from_raw_value(32 * 2977044472);
        let actual_ln = fixed_point32::create_from_raw_value(
            ln_plus_offset.get_raw_value() -
                offset.get_raw_value()
        );

        // Negate to get -ln(1-u)
        mul_div(actual_ln, complement, one)
    }

    #[test_only]
    fun multiple_sequential_dirichlet_hongbao(
        num_draws: u64,
        total_amount: u64,
        num_packets: u64,
    ): vector<FixedPoint32> {
        let result = vector::empty();
        let remaining_money = total_amount;
        let remaining_draws = num_packets;
        for (i in 0..num_draws) {
            let draw = sequential_dirichlet_hongbao(remaining_money, remaining_draws);
            result.push_back(draw);
            remaining_money -= draw.round();
            remaining_draws -= 1;
        };
        result
    }

    #[test_only]
    use aptos_std::debug::print;
    #[test_only]
    use aptos_std::string_utils;

    #[test_only]
    fun initialize(
        aptos_framework: &signer
    ) {
        randomness::initialize_for_testing(aptos_framework);
    }

    #[test(aptos_framework = @aptos_framework)]
    #[lint::allow_unsafe_randomness]
    public fun test_sequential_dirichlet_hongbao(aptos_framework: &signer) {
        initialize(aptos_framework);
        let total_amount: u64 = 1000;
        let num_packets: u64 = 10;
        for (i in 0..10) {
            let amounts = multiple_sequential_dirichlet_hongbao(num_packets, total_amount, num_packets);
            print(&string_utils::format1(&b"amounts: {}", amounts.map_ref(|x| (*x).round())));

            assert!(amounts.length() == num_packets);
            let sum: FixedPoint32 = fixed_point32::create_from_u64(0);
            amounts.for_each(|amount| {
                sum = fixed_point32::create_from_raw_value(sum.get_raw_value() + amount.get_raw_value());
            });
            print(&string_utils::format2(&b"sum: {}, total_amount: {}", sum, total_amount));
            let sum = sum.round();
            if (sum != total_amount) {
                print(&string_utils::format2(&b"sum: {}, total_amount: {}", sum, total_amount));
            };
            assert!(sum == total_amount);
        };
    }

    #[test(aptos_framework = @aptos_framework)]
    #[lint::allow_unsafe_randomness]
    public fun test_print_many_dirichlet_hongbao(aptos_framework: &signer) {
        initialize(aptos_framework);
        let test_runs = 1000;

        let total_amount: u64 = 3250;
        let num_packets: u64 = 17;
        for (i in 0..test_runs) {
            let amounts = multiple_sequential_dirichlet_hongbao(num_packets, total_amount, num_packets);
            print(&string_utils::format1(&b"amounts: {}", amounts.map_ref(|x| (*x).round())));
        };
    }
}