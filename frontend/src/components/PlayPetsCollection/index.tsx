import React, { useEffect } from "react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useGetPlayPetsCollection } from "@/hooks/useGetPlayPetsCollection";

export function PlayPetsCollection() {
  const { account, network } = useWallet();
  const { collection, firstFewPlayPetsName, loading, fetchCollection } =
    useGetPlayPetsCollection();

  useEffect(() => {
    if (!account?.address || !network) return;
    fetchCollection();
  }, [account?.address, fetchCollection, network]);

  if (loading || !collection) return null;

  return (
    <div className="nes-container with-title sm:h-[100px]">
      <p>{`There are a total of ${collection.current_supply} PlayPets in existence.`}</p>
      <p>{`Meet your fellow PlayPets: ${firstFewPlayPetsName?.join(", ")}${
        (firstFewPlayPetsName?.length || 0) < collection.current_supply
          ? "..."
          : ""
      }`}</p>
    </div>
  );
}
