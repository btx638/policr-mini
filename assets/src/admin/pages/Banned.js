import React from "react";
import { PageHeader, PageLoading, NotImplemented } from "../components";
import { useSelector } from "react-redux";
import "twin.macro";

export default () => {
  const { isLoaded } = useSelector((state) => state.chats);

  return (
    <>
      <PageHeader title="封禁记录" />
      {isLoaded ? <NotImplemented /> : <PageLoading />}
    </>
  );
};
