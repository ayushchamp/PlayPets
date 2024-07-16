module playpets_addr::main {
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use aptos_framework::object::ExtendRef;
    use aptos_std::string_utils::{to_string};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use std::error;
    use std::option;
    use std::signer::address_of;
    use std::signer;
    use std::string::{Self, String};

    /// playpets not available
    const ENOT_AVAILABLE: u64 = 1;
    /// name length exceeded limit
    const ENAME_LIMIT: u64 = 2;
    /// user already has playpets
    const EUSER_ALREADY_HAS_PLAYPETS: u64 = 3;
    /// invalid body value
    const EBODY_VALUE_INVALID: u64 = 4;
    /// invalid ear value
    const EEAR_VALUE_INVALID: u64 = 5;
    /// invalid face value
    const EFACE_VALUE_INVALID: u64 = 6;

    // maximum health points: 5 hearts * 2 HP/heart = 10 HP
    const ENERGY_UPPER_BOUND: u64 = 10;
    const NAME_UPPER_BOUND: u64 = 40;

    struct PlayPetsParts has copy, drop, key, store {
        body: u8,
        ear: u8,
        face: u8,
    }

    struct PlayPets has key {
        name: String,
        birthday: u64,
        energy_points: u64,
        parts: PlayPetsParts,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
    }

    #[event]
    struct MintPlayPetsEvent has drop, store {
        token_name: String,
        playpets_name: String,
        parts: PlayPetsParts,
    }

    // We need a contract signer as the creator of the playpets collection and playpets token
    // Otherwise we need admin to sign whenever a new playpets token is minted which is inconvenient
    struct ObjectController has key {
        // This is the extend_ref of the app object, not the extend_ref of collection object or token object
        // app object is the creator and owner of playpets collection object
        // app object is also the creator of all playpets token (NFT) objects
        // but owner of each token object is playpets owner
        app_extend_ref: ExtendRef,
    }

    const APP_OBJECT_SEED: vector<u8> = b"PLAYPETS";
    const PLAYPETS_COLLECTION_NAME: vector<u8> = b"PlayPets Collection";
    const PLAYPETS_COLLECTION_DESCRIPTION: vector<u8> = b"PlayPets Collection Description";
    const PLAYPETS_COLLECTION_URI: vector<u8> = b"https://otjbxblyfunmfblzdegw.supabase.co/storage/v1/object/public/playpets/playpets.png";
    // Body value range is [0, 4] inslusive
    const BODY_MAX_VALUE: u8 = 4;
    // Ear value range is [0, 5] inslusive
    const EAR_MAX_VALUE: u8 = 6;
    // Face value range is [0, 3] inslusive
    const FACE_MAX_VALUE: u8 = 3;

    // This function is only called once when the module is published for the first time.
    fun init_module(account: &signer) {
        let constructor_ref = object::create_named_object(
            account,
            APP_OBJECT_SEED,
        );
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let app_signer = &object::generate_signer(&constructor_ref);

        move_to(app_signer, ObjectController {
            app_extend_ref: extend_ref,
        });

        create_playpets_collection(app_signer);
    }

    // ================================= Helper Functions ================================= //

    fun get_app_signer_addr(): address {
        object::create_object_address(&@playpets_addr, APP_OBJECT_SEED)
    }

    fun get_app_signer(): signer acquires ObjectController {
        object::generate_signer_for_extending(&borrow_global<ObjectController>(get_app_signer_addr()).app_extend_ref)
    }

    // Create the collection that will hold all the PlayPets
    fun create_playpets_collection(creator: &signer) {
        let description = string::utf8(PLAYPETS_COLLECTION_DESCRIPTION);
        let name = string::utf8(PLAYPETS_COLLECTION_NAME);
        let uri = string::utf8(PLAYPETS_COLLECTION_URI);

        collection::create_unlimited_collection(
            creator,
            description,
            name,
            option::none(),
            uri,
        );
    }

    // ================================= Entry Functions ================================= //

    // Create an PlayPets token object
    public entry fun create_playpets(
        user: &signer,
        name: String,
        body: u8,
        ear: u8,
        face: u8,
    ) acquires ObjectController {
        assert!(string::length(&name) <= NAME_UPPER_BOUND, error::invalid_argument(ENAME_LIMIT));
        assert!(
            body >= 0 && body <= BODY_MAX_VALUE,
            error::invalid_argument(EBODY_VALUE_INVALID)
        );
        assert!(ear >= 0 && ear <= EAR_MAX_VALUE, error::invalid_argument(EEAR_VALUE_INVALID));
        assert!(
            face >= 0 && face <= FACE_MAX_VALUE,
            error::invalid_argument(EFACE_VALUE_INVALID)
        );

        let uri = string::utf8(PLAYPETS_COLLECTION_URI);
        let description = string::utf8(PLAYPETS_COLLECTION_DESCRIPTION);
        let user_addr = address_of(user);
        let token_name = to_string(&user_addr);
        let parts = PlayPetsParts {
            body,
            ear,
            face,
        };
        assert!(!has_playpets(user_addr), error::already_exists(EUSER_ALREADY_HAS_PLAYPETS));

        let constructor_ref = token::create_named_token(
            &get_app_signer(),
            string::utf8(PLAYPETS_COLLECTION_NAME),
            description,
            token_name,
            option::none(),
            uri,
        );

        let token_signer = object::generate_signer(&constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);

        // initialize/set default PlayPets struct values
        let gotchi = PlayPets {
            name,
            birthday: timestamp::now_seconds(),
            energy_points: ENERGY_UPPER_BOUND,
            parts,
            mutator_ref,
            burn_ref,
        };

        move_to(&token_signer, gotchi);

        // Emit event for minting PlayPets token
        event::emit<MintPlayPetsEvent>(
            MintPlayPetsEvent {
                token_name,
                playpets_name: name,
                parts,
            },
        );

        object::transfer_with_ref(object::generate_linear_transfer_ref(&transfer_ref), address_of(user));
    }

    // Sets PlayPets's name
    public entry fun set_name(owner: signer, name: String) acquires PlayPets {
        let owner_addr = signer::address_of(&owner);
        assert!(has_playpets(owner_addr), error::unavailable(ENOT_AVAILABLE));
        assert!(string::length(&name) <= NAME_UPPER_BOUND, error::invalid_argument(ENAME_LIMIT));
        let token_address = get_playpets_address(owner_addr);
        let gotchi = borrow_global_mut<PlayPets>(token_address);
        gotchi.name = name;
    }

    // Feeds PlayPets to increase its energy points
    public entry fun feed(owner: &signer, points: u64) acquires PlayPets {
        let owner_addr = signer::address_of(owner);
        assert!(has_playpets(owner_addr), error::unavailable(ENOT_AVAILABLE));
        let token_address = get_playpets_address(owner_addr);
        let gotchi = borrow_global_mut<PlayPets>(token_address);

        gotchi.energy_points = if (gotchi.energy_points + points > ENERGY_UPPER_BOUND) {
            ENERGY_UPPER_BOUND
        } else {
            gotchi.energy_points + points
        };
    }

    // Plays with PlayPets to consume its energy points
    public entry fun play(owner: &signer, points: u64) acquires PlayPets {
        let owner_addr = signer::address_of(owner);
        assert!(has_playpets(owner_addr), error::unavailable(ENOT_AVAILABLE));
        let token_address = get_playpets_address(owner_addr);
        let gotchi = borrow_global_mut<PlayPets>(token_address);

        gotchi.energy_points = if (gotchi.energy_points < points) {
            0
        } else {
            gotchi.energy_points - points
        };
    }

    // Sets PlayPets's parts
    public entry fun set_parts(owner: &signer, body: u8, ear: u8, face: u8) acquires PlayPets {
        let owner_addr = signer::address_of(owner);
        assert!(has_playpets(owner_addr), error::unavailable(ENOT_AVAILABLE));
        let token_address = get_playpets_address(owner_addr);
        let gotchi = borrow_global_mut<PlayPets>(token_address);
        gotchi.parts.body = body;
        gotchi.parts.ear = ear;
        gotchi.parts.face = face;
    }

    // ================================= View Functions ================================== //

    // Get reference to PlayPets token object (CAN'T modify the reference)
    #[view]
    public fun get_playpets_address(creator_addr: address): (address) {
        let collection = string::utf8(PLAYPETS_COLLECTION_NAME);
        let token_name = to_string(&creator_addr);
        let creator_addr = get_app_signer_addr();
        let token_address = token::create_token_address(
            &creator_addr,
            &collection,
            &token_name,
        );

        token_address
    }

    // Get collection address (also known as collection ID) of PlayPets collection
    // Collection itself is an object, that's why it has an address
    #[view]
    public fun get_playpets_collection_address(): (address) {
        let collection_name = string::utf8(PLAYPETS_COLLECTION_NAME);
        let creator_addr = get_app_signer_addr();
        collection::create_collection_address(&creator_addr, &collection_name)
    }

    // Returns true if this address owns an PlayPets
    #[view]
    public fun has_playpets(owner_addr: address): (bool) {
        let token_address = get_playpets_address(owner_addr);

        exists<PlayPets>(token_address)
    }

    // Returns all fields for this PlayPets (if found)
    #[view]
    public fun get_playpets(
        owner_addr: address
    ): (String, u64, u64, PlayPetsParts) acquires PlayPets {
        // if this address doesn't have an PlayPets, throw error
        assert!(has_playpets(owner_addr), error::unavailable(ENOT_AVAILABLE));

        let token_address = get_playpets_address(owner_addr);
        let gotchi = borrow_global<PlayPets>(token_address);

        // view function can only return primitive types.
        (gotchi.name, gotchi.birthday, gotchi.energy_points, gotchi.parts)
    }

    // ================================= Unit Tests ================================== //

    // Setup testing environment
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    #[test_only]
    use std::string::utf8;

    #[test_only]
    fun setup_test(aptos: &signer, account: &signer, creator: &signer) {
        // create a fake account (only for testing purposes)
        create_account_for_test(signer::address_of(creator));
        create_account_for_test(signer::address_of(account));

        timestamp::set_time_has_started_for_testing(aptos);
        init_module(account);
    }

    // Test creating an PlayPets
    #[test(aptos = @0x1, account = @playpets_addr, creator = @0x123)]
    fun test_create_playpets(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires ObjectController {
        setup_test(aptos, account, creator);

        create_playpets(creator, utf8(b"test"), 1, 1, 1);

        let has_playpets = has_playpets(signer::address_of(creator));
        assert!(has_playpets, 1);
    }

    // Test getting an PlayPets, when user has not minted
    #[test(aptos = @0x1, account = @playpets_addr, creator = @0x123)]
    #[expected_failure(abort_code = 851969, location = playpets_addr::main)]
    fun test_get_playpets_without_creation(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires PlayPets {
        setup_test(aptos, account, creator);

        // get playpets without creating it
        get_playpets(signer::address_of(creator));
    }

    // Test getting an PlayPets, when user has not minted
    #[test(aptos = @0x1, account = @playpets_addr, creator = @0x123)]
    fun test_feed_and_play(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires ObjectController, PlayPets {
        setup_test(aptos, account, creator);
        let creator_address = signer::address_of(creator);
        create_playpets(creator, utf8(b"test"), 1, 1, 1);

        let (_, _, energe_point_1, _) = get_playpets(creator_address);
        assert!(energe_point_1 == ENERGY_UPPER_BOUND, 1);

        play(creator, 5);
        let (_, _, energe_point_2, _) = get_playpets(creator_address);
        assert!(energe_point_2 == ENERGY_UPPER_BOUND - 5, 1);

        feed(creator, 3);
        let (_, _, energe_point_3, _) = get_playpets(creator_address);
        assert!(energe_point_3 == ENERGY_UPPER_BOUND - 2, 1);
    }

    // Test getting an PlayPets, when user has not minted
    #[test(aptos = @0x1, account = @playpets_addr, creator = @0x123)]
    #[expected_failure(abort_code = 524291, location = playpets_addr::main)]
    fun test_create_playpets_twice(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires ObjectController {
        setup_test(aptos, account, creator);

        create_playpets(creator, utf8(b"test"), 1, 1, 1);
        create_playpets(creator, utf8(b"test"), 1, 1, 1);
    }
}
