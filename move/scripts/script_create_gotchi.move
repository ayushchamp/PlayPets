script {
    use std::string::utf8;

    fun create_gotchi(user: &signer) {
        let gotchi_name = utf8(b"gotchi");
        playpets_addr::main::create_playpets(user, gotchi_name, 1, 1, 1);
    }
}
